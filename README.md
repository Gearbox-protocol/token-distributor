# Gearbox protocol

Gearbox is a generalized leverage protocol: it allows you to take leverage in one place and then use it across various
DeFi protocols and platforms in a composable way. The protocol has two sides to it: passive liquidity providers who earn higher APY
by providing liquidity; active traders, farmers, or even other protocols who can borrow those assets to trade or farm with x4+ leverage.

## Repository overview

This repository contains the distributor contract for the Gearbox DAO GEAR token. The purpose of the distributor contract is twofold:

- Deploy new vesting contracts to distribute GEAR to DAO participants and investors;
- Count the GEAR tokens locked in vesting in Gearbox DAO voting, with appropriate weights;

## How to use

### Roles

The `TokenDistributor.sol` contract has two main access roles:
1) Treasury is the Gearbox DAO financial multisig / contract; it can change voting weights and add new ones, as well as set the distribution controller;
2) The distribution controller is the EOA or a contract address appointed by the treasury; it can deploy new vesting contracts (that are recognized and accounted for by `TokenDistributor`) and clean up already emptied contracts from corresponding lists.

### Token dsitribution

Note that while the distribution controller can deploy new vesting contracts by calling `distributeTokens()`, they do not have direct access to minting / transferring GEAR. It is intended for the treasury to verify the conditions of deployed vesting contracts, and then directly send the appropriate amount of GEAR to each contract.

### Updating receivers

If the current receiver manually calls `setReceiver()` inside `StepVesting`, the distribution controller must call `updateContributor()` for the previous receiver, so that votes are correctly counted for the new receiver. Alternatively `updateContributors()` can be called, which will update receivers and clean up unused vesting contracts for all contributors.

## Bug bounty

This repository is subject to the Gearbox bug bounty program, per the terms defined [here]().

## Documentation

General documentation of the Gearbox Protocol can be found [here](https://docs.gearbox.fi). Developer documentation with
more tech-related infromation about the protocol, contract interfaces, integration guides and audits is available on the
[Gearbox dev protal](https://dev.gearbox.fi).

## Testing

### Setup

Running Forge unit tests requires Foundry. See [Foundry Book](https://book.getfoundry.sh/getting-started/installation) for installation details.

### Solidity unit tests

`forge t`

## Licensing

The contracts in this repository are licensed under GPL-2.0-or-later. The licensed files have appropriate SPDX headers.

## Disclaimer

This application is provided "as is" and "with all faults." Me as developer makes no representations or
warranties of any kind concerning the safety, suitability, lack of viruses, inaccuracies, typographical
errors, or other harmful components of this software. There are inherent dangers in the use of any software,
and you are solely responsible for determining whether this software product is compatible with your equipment and
other software installed on your equipment. You are also solely responsible for the protection of your equipment
and backup of your data, and THE PROVIDER will not be liable for any damages you may suffer in connection with using,
modifying, or distributing this software product.
