// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { vm } from "@chimera/Hevm.sol";
import { console2 } from "forge-std/console2.sol";

import { Setup } from "./Setup.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";

abstract contract DepositQueueTargets is BaseTargetFunctions, Setup {
    /// @notice this is a privileged function that's called by an ERC20RewardsAdmin admin to sweep ERC20 rewards tokens into RestakeManager
    function depositQueue_depositTokenRewardsFromProtocol(uint256 tokenIndex) public {
        address tokenToDeposit = _getRandomDepositableToken(tokenIndex);

        depositQueue.sweepERC20(IERC20(tokenToDeposit));
    }

    /// @dev currently ETH deposit contract is being mocked by ETHPOSDepositMock so signature values are irrelevant
    function depositQueue_stakeEthFromQueue(
        uint256 operatorDelegatorIndex,
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) public {
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        // creates a validator deployed via an EigenPod once the DepositQueue has at least 32 ETH in it
        depositQueue.stakeEthFromQueue(operatorDelegator, pubkey, signature, depositDataRoot);

        // update shares of the OperatorDelegator (EigenPod owner) to simulate a validation of a beacon chain state proof of the validator balance
        address podAddress = address(eigenPodManager.getPod(address(operatorDelegator)));
        vm.prank(podAddress);
        eigenPodManager.recordBeaconChainETHBalanceUpdate(address(operatorDelegator), 32 ether);
    }

    /// @notice needed for handling gas refunds from call to stakeEthFromQueue
    fallback() external {}
}
