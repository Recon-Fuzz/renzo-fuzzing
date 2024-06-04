// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { vm } from "@chimera/Hevm.sol";
import { console2 } from "forge-std/console2.sol";

import { SetupV2 } from "./SetupV2.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";

abstract contract DepositQueueTargetsV2 is BaseTargetFunctions, SetupV2 {
    // NOTE: this is a privileged function that's called by an ERC20RewardsAdmin admin to sweep ERC20 rewards tokens into RestakeManager
    // function depositQueue_depositTokenRewardsFromProtocol(uint256 tokenIndex) public {
    //     address tokenToDeposit = _getRandomDepositableToken(tokenIndex);

    //     // the call in depositQueue makes a call to depositTokenRewardsFromProtocol
    //     depositQueue.sweepERC20(IERC20(tokenToDeposit));
    // }

    // NOTE: this needs to be included to complete the native ETH staking process
    // @audit currently ETH deposit contract is being mocked by ETHPOSDepositMock so signature values are irrelevant
    function depositQueue_stakeEthFromQueue(
        uint256 operatorDelegatorIndex,
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) public {
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        // @audit added this in for testing full flow, comment out for live testing
        // try restakeManager.depositETH{ value: 32 ether }() {
        //     // t(false, "call to depositETH succeeeds");
        // } catch {
        //     // t(false, "call to depositETH fails");
        // }

        // this creates a validator deployed via an EigenPod once the DepositQueue has at least 32 ETH in it
        depositQueue.stakeEthFromQueue(operatorDelegator, pubkey, signature, depositDataRoot);

        // update shares of the OperatorDelegator (EigenPod owner) to simulate a validation of a beacon chain state proof of the validator balance
        // NOTE: shares of EigenPod are exchangeable 1:1 with the ETH staked in the validator node
        address podAddress = address(eigenPodManager.getPod(address(operatorDelegator)));
        // need to prank as the pod to be able ot update share accounting
        vm.prank(podAddress);
        eigenPodManager.recordBeaconChainETHBalanceUpdate(address(operatorDelegator), 32 ether);
    }
}
