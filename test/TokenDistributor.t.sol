// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TokenDistributor} from "../contracts/TokenDistributor.sol";
import {IGearToken} from "../contracts/interfaces/IGearToken.sol";
import {ITokenDistributorOld} from "../contracts/interfaces/ITokenDistributorOld.sol";
import {IAddressProvider} from "../contracts/interfaces/IAddressProvider.sol";
import {
    ITokenDistributorExceptions,
    ITokenDistributorEvents,
    TokenAllocationOpts
} from "../contracts/interfaces/ITokenDistributor.sol";
import {IStepVesting} from "../contracts/interfaces/IStepVesting.sol";
import {DUMB_ADDRESS, DUMB_ADDRESS2, CONTROLLER, SECONDS_PER_YEAR, WAD} from "./constants.sol";
import {PERCENTAGE_FACTOR} from "../contracts/helpers/Constants.sol";

address constant ADDRESS_PROVIDER = 0xcF64698AFF7E5f27A11dff868AF228653ba53be0;
address constant GEAR_TOKEN = 0xBa3335588D9403515223F109EdC4eB7269a9Ab5D;
address constant TOKEN_DISTRIBUTOR_OLD = 0xBF57539473913685688d224ad4E262684B23dD4c;

/// @title TokenDistributorTest
/// @notice Designed for unit test purposes only
contract TokenDistributorTest is Test, ITokenDistributorEvents, ITokenDistributorExceptions {
    TokenDistributor public tokenDistributor;
    ITokenDistributorOld public tokenDistributorOld;
    IGearToken public gearToken;
    IAddressProvider public addressProvider;

    address public root;

    function setUp() public {
        tokenDistributorOld = ITokenDistributorOld(TOKEN_DISTRIBUTOR_OLD);
        addressProvider = IAddressProvider(ADDRESS_PROVIDER);
        gearToken = IGearToken(GEAR_TOKEN);

        tokenDistributor = new TokenDistributor(
            addressProvider,
            tokenDistributorOld
        );

        vm.prank(addressProvider.getTreasuryContract());
        tokenDistributor.setDistributionController(CONTROLLER);

        root = Ownable(addressProvider.getACL()).owner();
    }

    function _distributeTokens(TokenAllocationOpts[] memory testOpts) internal {
        for (uint256 i; i < testOpts.length; ++i) {
            vm.prank(CONTROLLER);
            tokenDistributor.distributeTokens(
                testOpts[i].recipient,
                testOpts[i].votingCategory,
                testOpts[i].cliffDuration,
                testOpts[i].cliffAmount,
                testOpts[i].vestingDuration,
                testOpts[i].vestingNumSteps,
                testOpts[i].vestingAmount
            );
        }
    }

    /// @dev [TD-1]: Constructor sets correct values
    function test_TD_01_constructor_sets_correct_values() public {
        assertEq(
            tokenDistributor.masterVestingContract(),
            tokenDistributorOld.masterVestingContract(),
            "Master vesting contract incorrect"
        );

        assertEq(address(tokenDistributor.gearToken()), address(gearToken), "GEAR address incorrect");

        assertEq(tokenDistributor.treasury(), addressProvider.getTreasuryContract(), "Treasury incorrect");

        assertEq(
            tokenDistributor.votingCategoryMultipliers("TYPE_A"),
            tokenDistributorOld.weightA(),
            "Voting category A weight incorrect"
        );

        assertEq(
            tokenDistributor.votingCategoryMultipliers("TYPE_B"),
            tokenDistributorOld.weightB(),
            "Voting category B weight incorrect"
        );

        assertTrue(
            tokenDistributor.votingCategoryExists("TYPE_ZERO"),
            "Voting category zero not added"
        );

        // assertEq(
        //     tokenDistributor.countContributors(),
        //     tokenDistributorOld.countContributors(),
        //     "Contributors count incorrect"
        // );
    }

    /// @dev [TD-3]: TokenDistributor.distributeTokens works correctly and reverts on being called by non-treasury
    function test_TD_03_distributeTokens_works_correctly() public {
        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](3);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_A",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 100 * WAD,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: 365 * WAD
        });

        testOpts[1] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_B",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR * 2,
            vestingNumSteps: 365 * 2,
            vestingAmount: 365 * 4 * WAD
        });

        testOpts[2] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS2,
            votingCategory: "TYPE_ZERO",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR * 2,
            vestingNumSteps: 365 * 4,
            vestingAmount: 365 * 8 * WAD
        });

        vm.expectRevert(NotDistributionControllerException.selector);
        tokenDistributor.distributeTokens(
            testOpts[0].recipient,
            testOpts[0].votingCategory,
            testOpts[0].cliffDuration,
            testOpts[0].cliffAmount,
            testOpts[0].vestingDuration,
            testOpts[0].vestingNumSteps,
            testOpts[0].vestingAmount
        );

        vm.expectEmit(true, false, false, true);
        emit VestingContractAdded(DUMB_ADDRESS, address(0), 465 * WAD, "TYPE_A");

        vm.expectEmit(true, false, false, true);
        emit VestingContractAdded(DUMB_ADDRESS, address(0), 365 * 4 * WAD, "TYPE_B");

        vm.expectEmit(true, false, false, true);
        emit VestingContractAdded(DUMB_ADDRESS2, address(0), 365 * 8 * WAD, "TYPE_ZERO");

        _distributeTokens(testOpts);

        address[] memory vcs0 = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        assertEq(vcs0.length, 2, "Incorrect number of vesting contracts for contributor");

        // CHECKING VESTING CONTRACT 1

        assertEq(IStepVesting(vcs0[0]).cliffDuration(), SECONDS_PER_YEAR, "Incorrect cliff duration");

        assertEq(IStepVesting(vcs0[0]).stepDuration(), SECONDS_PER_YEAR / 365, "Incorrect step duration");

        assertEq(IStepVesting(vcs0[0]).cliffAmount(), 100 * WAD, "Incorrect cliff amount");

        assertEq(IStepVesting(vcs0[0]).stepAmount(), WAD, "Incorrect step amount");

        assertEq(IStepVesting(vcs0[0]).numOfSteps(), 365, "Incorrect number of steps");

        // CHECKING VESTING CONTRACT 2

        assertEq(IStepVesting(vcs0[1]).cliffDuration(), SECONDS_PER_YEAR, "Incorrect cliff duration");

        assertEq(IStepVesting(vcs0[1]).stepDuration(), SECONDS_PER_YEAR / 365, "Incorrect step duration");

        assertEq(IStepVesting(vcs0[1]).cliffAmount(), 0, "Incorrect cliff amount");

        assertEq(IStepVesting(vcs0[1]).stepAmount(), 2 * WAD, "Incorrect step amount");

        assertEq(IStepVesting(vcs0[1]).numOfSteps(), 365 * 2, "Incorrect number of steps");

        address[] memory vcs1 = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS2);

        assertEq(vcs1.length, 1, "Incorrect number of vesting contracts for contributor");

        // CHECKING VESTING CONTRACT 3

        assertEq(IStepVesting(vcs1[0]).cliffDuration(), SECONDS_PER_YEAR, "Incorrect cliff duration");

        assertEq(IStepVesting(vcs1[0]).stepDuration(), SECONDS_PER_YEAR / 365 / 2, "Incorrect step duration");

        assertEq(IStepVesting(vcs1[0]).cliffAmount(), 0, "Incorrect cliff amount");

        assertEq(IStepVesting(vcs1[0]).stepAmount(), 2 * WAD, "Incorrect step amount");

        assertEq(IStepVesting(vcs1[0]).numOfSteps(), 365 * 4, "Incorrect number of steps");
    }

    /// @dev [TD-5]: balanceOf returns expected amount
    function test_TD_05_balanceOf_returns_expected_amount(
        uint256 cliffAmount0,
        uint256 vestingAmount0,
        uint16 votingMultiplier0,
        uint256 cliffAmount1,
        uint256 vestingAmount1,
        uint16 votingMultiplier1,
        uint256 userBalance
    ) public {
        vm.assume(cliffAmount0 < 100000000 * WAD);
        vm.assume(vestingAmount0 < 100000000 * WAD);
        vm.assume(votingMultiplier0 <= 10000);

        vm.assume(cliffAmount1 < 100000000 * WAD);
        vm.assume(vestingAmount1 < 100000000 * WAD);
        vm.assume(votingMultiplier1 <= 10000);

        vm.assume(userBalance < 100000000 * WAD);

        address treasury = addressProvider.getTreasuryContract();

        vm.prank(treasury);
        tokenDistributor.updateVotingCategoryMultiplier("TYPE_TEST0", votingMultiplier0);

        vm.prank(treasury);
        tokenDistributor.updateVotingCategoryMultiplier("TYPE_TEST1", votingMultiplier1);

        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](2);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_TEST0",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: cliffAmount0,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: vestingAmount0
        });

        testOpts[1] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_TEST1",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: cliffAmount1,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: vestingAmount1
        });

        hoax(treasury);
        gearToken.transfer(DUMB_ADDRESS, userBalance);

        _distributeTokens(testOpts);

        uint256 expectedAmount = userBalance + ((cliffAmount0 + vestingAmount0) * votingMultiplier0) / PERCENTAGE_FACTOR
            + ((cliffAmount1 + vestingAmount1) * votingMultiplier1) / PERCENTAGE_FACTOR;

        address[] memory vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        hoax(treasury);
        gearToken.transfer(vcs[0], cliffAmount0 + vestingAmount0);

        hoax(treasury);
        gearToken.transfer(vcs[1], cliffAmount1 + vestingAmount1);

        assertEq(tokenDistributor.balanceOf(DUMB_ADDRESS), expectedAmount, "Reported balance incorrect");
    }

    /// @dev [TD-6]: updateVotingCategoryMultiplier sets correct value and emits an event
    function test_TD_06_updateVotingCategoryMultiplier_works_correctly() public {
        vm.expectRevert(NotTreasuryException.selector);
        tokenDistributor.updateVotingCategoryMultiplier("TYPE_TEST0", 1000);

        address treasury = addressProvider.getTreasuryContract();

        vm.expectEmit(true, false, false, true);
        emit NewVotingMultiplier("TYPE_TEST0", 1000);

        vm.prank(treasury);
        tokenDistributor.updateVotingCategoryMultiplier("TYPE_TEST0", 1000);

        assertEq(tokenDistributor.votingCategoryMultipliers("TYPE_TEST0"), 1000);
    }

    /// @dev [TD-7]: updateContributor works correctly
    function test_TD_07_updateContributor_works_correctly() public {
        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](1);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_A",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: 365 * WAD
        });

        address treasury = addressProvider.getTreasuryContract();

        _distributeTokens(testOpts);

        address[] memory vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        address vc0 = vcs[0];

        hoax(treasury);
        gearToken.transfer(vc0, 365 * WAD);

        vm.prank(DUMB_ADDRESS);
        IStepVesting(vc0).setReceiver(DUMB_ADDRESS2);

        tokenDistributor.updateContributor(DUMB_ADDRESS);

        vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS2);

        assertEq(vcs.length, 1, "Second contributor was not updated");

        assertEq(vcs[0], vc0, "Contract receiver was not changed");
    }

    /// @dev [TD-7A]: cleanupContributor works correctly
    function test_TD_07A_cleanupContributor_works_correctly() public {
        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](1);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_A",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: 365 * WAD
        });

        address treasury = addressProvider.getTreasuryContract();

        _distributeTokens(testOpts);

        address[] memory vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        address vc0 = vcs[0];

        hoax(treasury);
        gearToken.transfer(vc0, 365 * WAD);

        vm.prank(DUMB_ADDRESS);
        IStepVesting(vc0).setReceiver(DUMB_ADDRESS2);

        deal(address(gearToken), vc0, 0);

        vm.expectRevert(NotDistributionControllerException.selector);
        tokenDistributor.cleanupContributor(DUMB_ADDRESS);

        hoax(CONTROLLER);
        tokenDistributor.cleanupContributor(DUMB_ADDRESS);

        hoax(CONTROLLER);
        vm.expectRevert(abi.encodeWithSelector(ContributorNotRegisteredException.selector, DUMB_ADDRESS));
        tokenDistributor.cleanupContributor(DUMB_ADDRESS);

    }

    /// @dev [TD-8]: updateContributors works correctly
    function test_TD_08_updateContributors_works_correctly() public {
        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](2);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_A",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: 365 * WAD
        });

        testOpts[1] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS2,
            votingCategory: "TYPE_B",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR * 2,
            vestingNumSteps: 365 * 2,
            vestingAmount: 365 * 4 * WAD
        });

        address treasury = addressProvider.getTreasuryContract();

        _distributeTokens(testOpts);

        address[] memory vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        address vc0 = vcs[0];

        hoax(treasury);
        gearToken.transfer(vc0, 365 * WAD);

        vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS2);

        address vc1 = vcs[0];

        hoax(treasury);
        gearToken.transfer(vc1, 365 * 4 * WAD);

        vm.prank(DUMB_ADDRESS);
        IStepVesting(vc0).setReceiver(DUMB_ADDRESS2);

        vm.prank(DUMB_ADDRESS2);
        IStepVesting(vc1).setReceiver(DUMB_ADDRESS);

        tokenDistributor.updateContributors();

        vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS2);

        assertEq(vcs.length, 1, "Second contributor was not updated");

        assertEq(vcs[0], vc0, "Contract receiver was not changed");

        vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        assertEq(vcs.length, 1, "Second contributor was not updated");

        assertEq(vcs[0], vc1, "Contract receiver was not changed");
    }

    /// @dev [TD-8A]: cleanupContributors works correctly
    function test_TD_08A_cleanupContributors_works_correctly() public {
        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](2);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "TYPE_A",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: 365 * WAD
        });

        testOpts[1] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS2,
            votingCategory: "TYPE_B",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 0,
            vestingDuration: SECONDS_PER_YEAR * 2,
            vestingNumSteps: 365 * 2,
            vestingAmount: 365 * 4 * WAD
        });

        address treasury = addressProvider.getTreasuryContract();

        _distributeTokens(testOpts);

        address[] memory vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS);

        address vc0 = vcs[0];

        hoax(treasury);
        gearToken.transfer(vc0, 365 * WAD);

        deal(address(gearToken), vc0, 0);

        vcs = tokenDistributor.contributorVestingContracts(DUMB_ADDRESS2);

        address vc2 = vcs[0];

        hoax(treasury);
        gearToken.transfer(vc2, 365 * 4 * WAD);

        deal(address(gearToken), vc2, 0);

        vm.expectRevert(NotDistributionControllerException.selector);
        tokenDistributor.cleanupContributors();

        hoax(CONTROLLER);
        tokenDistributor.cleanupContributors();

        vm.expectRevert(abi.encodeWithSelector(ContributorNotRegisteredException.selector, DUMB_ADDRESS));
        hoax(CONTROLLER);
        tokenDistributor.updateContributor(DUMB_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(ContributorNotRegisteredException.selector, DUMB_ADDRESS2));
        hoax(CONTROLLER);
        tokenDistributor.updateContributor(DUMB_ADDRESS2);
    }

    function test_TD_09_setDistributionController_works_correctly() public {
        address treasury = addressProvider.getTreasuryContract();

        vm.expectRevert(NotTreasuryException.selector);
        tokenDistributor.setDistributionController(DUMB_ADDRESS2);

        vm.prank(treasury);
        tokenDistributor.setDistributionController(DUMB_ADDRESS2);

        assertEq(tokenDistributor.distributionController(), DUMB_ADDRESS2, "Distribution controller was not set");
    }

    function test_TD_10_setDistributionController_works_correctly() public {
        TokenAllocationOpts[] memory testOpts = new TokenAllocationOpts[](1);

        testOpts[0] = TokenAllocationOpts({
            recipient: DUMB_ADDRESS,
            votingCategory: "NOT_IN_THE_LIST",
            cliffDuration: SECONDS_PER_YEAR,
            cliffAmount: 100 * WAD,
            vestingDuration: SECONDS_PER_YEAR,
            vestingNumSteps: 365,
            vestingAmount: 365 * WAD
        });

        vm.expectRevert(VotingCategoryDoesntExist.selector);
        _distributeTokens(testOpts);
    }
}
