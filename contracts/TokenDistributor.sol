// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { PERCENTAGE_FACTOR } from "./helpers/Constants.sol";

import { IAddressProvider } from "./interfaces/IAddressProvider.sol";
import { IGearToken } from "./interfaces/IGearToken.sol";
import { StepVesting } from "./Vesting.sol";
import { IStepVesting } from "./interfaces/IStepVesting.sol";
import { ITokenDistributorOld, VestingContract, VotingPower } from "./interfaces/ITokenDistributorOld.sol";

contract TokenDistributor {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Address of the treasury
    address treasury;

    /// @dev Struct containing parameters to initialize a new vesting contract
    struct TokenAllocationOpts {
        address recipient;
        string votingCategory;
        uint256 cliffDuration;
        uint256 cliffAmount;
        uint256 vestingDuration;
        uint256 vestingNumSteps;
        uint256 vestingAmount;
    }

    /// @dev GEAR token
    IGearToken public gearToken;

    /// @dev Address of master contract to clone
    address public immutable masterVestingContract;

    /// @dev Mapping from contributor addresses to their active vesting contracts
    mapping(address => EnumerableSet.AddressSet) internal vestingContracts;

    /// @dev Mapping from vesting contracts to their voting power categories
    mapping(address => string) internal vestingContractVotingCategory;

    /// @dev Mapping from voting categories to corresponding voting power multipliers
    mapping(string => uint16) public votingCategoryMultipliers;

    /// @dev Set of all known contributors
    EnumerableSet.AddressSet private contributorsSet;

    /// @dev Thrown if there is leftover GEAR in the contract after distribution
    error NonZeroBalanceAfterDistributionException(uint256 amount);

    /// @dev Thrown if attempting to do an action for an address that is not a contributor
    error ContributorNotRegisteredException(address user);

    /// @dev Emits when a multiplier for a voting category is updated
    event NewVotingMultiplier(string indexed category, uint16 multiplier);

    /// @dev Emits when a new vesting contract is added
    event VestingContractAdded(
        address indexed holder,
        address indexed vestingContract,
        uint256 amount,
        string votingPowerCategory
    );

    /// @dev Emits when the contributor associated with a vesting contract is changed
    event VestingContractReceiverUpdated(
        address indexed vestingContract,
        address indexed prevReceiver,
        address indexed newReceiver
    );

    /// @param addressProvider address of Address provider
    /// @param tokenDistributorOld Address of the previous token distributor
    constructor(
        IAddressProvider addressProvider,
        ITokenDistributorOld tokenDistributorOld
    ) {
        masterVestingContract = tokenDistributorOld.masterVestingContract();
        gearToken = IGearToken(addressProvider.getGearToken()); // T:[TD-1]
        treasury = addressProvider.getTreasuryContract();

        uint16 weightA = uint16(tokenDistributorOld.weightA());
        uint16 weightB = uint16(tokenDistributorOld.weightB());

        votingCategoryMultipliers["TYPE_A"] = weightA;
        votingCategoryMultipliers["TYPE_B"] = weightB;

        emit NewVotingMultiplier("TYPE_A", weightA);
        emit NewVotingMultiplier("TYPE_B", weightB);
        emit NewVotingMultiplier("TYPE_ZERO", 0);

        address[] memory oldContributors = tokenDistributorOld
            .contributorsList();

        uint256 numOldContributors = oldContributors.length;

        for (uint256 i = 0; i < numOldContributors; ++i) {
            VestingContract memory vc = tokenDistributorOld.vestingContracts(
                oldContributors[i]
            );

            _addVestingContractForContributor(
                oldContributors[i],
                vc.contractAddress
            );

            string memory votingCategory = vc.votingPower == VotingPower.A
                ? "TYPE_A"
                : vc.votingPower == VotingPower.B
                ? "TYPE_B"
                : "TYPE_ZERO";

            vestingContractVotingCategory[vc.contractAddress] = votingCategory;

            emit VestingContractAdded(
                oldContributors[i],
                vc.contractAddress,
                gearToken.balanceOf(vc.contractAddress),
                votingCategory
            );
        }
    }

    modifier treasuryOnly() {
        if (msg.sender != treasury) {
            revert("Function is restricted to financial multisig");
        }
        _;
    }

    /// @dev Returns the total GEAR balance of holder, including vested balances weighted with their respective
    ///      voting category multipliers. Used in snapshot voting.
    /// @param holder Address to calculate the weighted balance for
    function balanceOf(address holder)
        external
        view
        returns (uint256 vestedBalanceWeighted)
    {
        uint256 numVestingContracts = vestingContracts[holder].length();

        for (uint256 i = 0; i < numVestingContracts; ++i) {
            address vc = vestingContracts[holder].at(i);
            address receiver = IStepVesting(vc).receiver();

            if (receiver == holder) {
                vestedBalanceWeighted +=
                    (gearToken.balanceOf(vc) *
                        votingCategoryMultipliers[
                            vestingContractVotingCategory[vc]
                        ]) /
                    PERCENTAGE_FACTOR;
            }
        }

        vestedBalanceWeighted += gearToken.balanceOf(holder);
    }

    //
    // VESTING CONTRACT CONTROLS
    //

    /// @dev Creates a batch of new GEAR vesting contracts with passed parameters
    /// @param opts Parameters for each vesting contract
    ///             * recipient - Address to set as the vesting contract receiver
    ///             * votingCategory - The voting category used to determine the vested GEARs' voting weight
    ///             * cliffDuration - time until first payout
    ///             * cliffAmount - size of first payout
    ///             * vestingDuration - time until all tokens are unlocked, starting from cliff
    ///             * vestingNumSteps - number of ticks at which tokens are unlocked
    ///             * vestingAmount - total number of tokens unlocked during the vesting period (excluding cliff)
    function distributeTokens(TokenAllocationOpts[] calldata opts)
        external
        treasuryOnly
    {
        for (uint256 i = 0; i < opts.length; ++i) {
            _deployVestingContract(opts[i]);
        }

        uint256 finalBalance = gearToken.balanceOf(address(this));

        if (finalBalance != 0) {
            revert NonZeroBalanceAfterDistributionException(finalBalance);
        }
    }

    //
    // CONTRIBUTOR HOUSEKEEPING
    //

    /// @dev Cleans up exhausted vesting contracts and aligns the receiver between this contract
    ///      and vesting contracts, for a particular contributor
    function updateContributor(address contributor) public {

        if (!contributorsSet.contains(contributor)) {
            revert ContributorNotRegisteredException(contributor);
        }
        _cleanupContributor(contributor);
    }

    /// @dev Cleans up exhausted vesting contracts and aligns the receiver between this contract
    ///      and vesting contracts, for all recorded contributors
    function updateContributors() external {
        address[] memory contributorsArray = contributorsSet.values();
        uint256 numContributors = contributorsArray.length;

        for (uint256 i = 0; i < numContributors; i++) {
            _cleanupContributor(contributorsArray[i]);
        }
    }

    //
    // VOTING POWER CONTROLS
    //

    /// @dev Updates the voting weight for a particular voting category
    /// @param category The name of the category to update the multiplier for
    /// @param multiplier The voting power weight for all vested GEAR belonging to the category
    function updateVotingCategoryMultiplier(
        string calldata category,
        uint16 multiplier
    ) external treasuryOnly {
        if (multiplier > PERCENTAGE_FACTOR) {
            revert("Multiplier can't be greater than 1");
        }

        votingCategoryMultipliers[category] = multiplier;
        emit NewVotingMultiplier(category, multiplier);
    }

    //
    // GETTERS
    //

    /// @dev Returns the number of recorded contributors
    function countContributors() external view returns (uint256) {
        return contributorsSet.length();
    }

    /// @dev Returns the full list of recorded contributors
    function contributorsList() external view returns (address[] memory) {
        address[] memory result = new address[](contributorsSet.length());

        for (uint256 i = 0; i < contributorsSet.length(); i++) {
            result[i] = contributorsSet.at(i);
        }

        return result;
    }

    /// @dev Returns the active vesting contracts for a particular contributor
    function contributorVestingContracts(address contributor)
        external
        view
        returns (address[] memory)
    {
        return vestingContracts[contributor].values();
    }

    //
    // INTERNAL FUNCTIONS
    //

    /// @dev Deploys a vesting contract for a new allocation
    function _deployVestingContract(TokenAllocationOpts memory opts) internal {
        address vc = Clones.clone(address(masterVestingContract));

        IStepVesting(vc).initialize(
            gearToken,
            block.timestamp,
            opts.cliffDuration,
            opts.vestingDuration / opts.vestingNumSteps,
            opts.cliffAmount,
            opts.vestingAmount / opts.vestingNumSteps,
            opts.vestingNumSteps,
            opts.recipient
        );

        _addVestingContractForContributor(opts.recipient, vc);

        vestingContractVotingCategory[vc] = opts.votingCategory;

        gearToken.transfer(vc, opts.cliffAmount + opts.vestingAmount);

        emit VestingContractAdded(
            opts.recipient,
            vc,
            opts.cliffAmount + opts.vestingAmount,
            opts.votingCategory
        );
    }

    /// @dev Cleans up all vesting contracts currently belonging to a contributor
    ///      If there are no more active vesting contracts after cleanup, removes
    ///      the contributor from the list
    function _cleanupContributor(address contributor) internal {
        address[] memory vcs = vestingContracts[contributor].values();
        uint256 numVestingContracts = vcs.length;

        for (uint256 i = 0; i < numVestingContracts; ) {
            address vc = vcs[i];
            _cleanupVestingContract(contributor, vc);

            unchecked {
                ++i;
            }
        }

        if (vestingContracts[contributor].length() == 0) {
            contributorsSet.remove(contributor);
        }
    }

    /// @dev Removes the contract from the list if it was exhausted, or
    ///      updates the associated contributor if the receiver was changed
    function _cleanupVestingContract(address contributor, address vc) internal {
        address receiver = IStepVesting(vc).receiver();

        if (gearToken.balanceOf(vc) == 0) {
            vestingContracts[contributor].remove(vc);
        } else if (receiver != contributor) {
            vestingContracts[contributor].remove(vc);
            _addVestingContractForContributor(receiver, vc);
            emit VestingContractReceiverUpdated(vc, contributor, receiver);
        }
    }

    /// @dev Associates a vesting contract with a contributor, and adds a contributor
    ///      to the list, if it did not exist before
    function _addVestingContractForContributor(address contributor, address vc)
        internal
    {
        if (!contributorsSet.contains(contributor)) {
            contributorsSet.add(contributor);
        }

        vestingContracts[contributor].add(vc);
    }
}
