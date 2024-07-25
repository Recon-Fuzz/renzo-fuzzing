// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";
import { console2 } from "forge-std/console2.sol";

import { Setup } from "./Setup.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";
import { OperatorDelegator } from "../../../contracts/Delegation/OperatorDelegator.sol";
import {
    IDelegationManager
} from "../../../contracts/EigenLayer/interfaces/IDelegationManager.sol";
import { IStrategy } from "../../../contracts/EigenLayer/interfaces/IStrategy.sol";
import { BeforeAfter } from "./BeforeAfter.sol";

abstract contract OperatorDelegatorTargets is BaseTargetFunctions, Setup, BeforeAfter {
    address internal constant IS_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IDelegationManager.Withdrawal[] eigenLayerWithdrawalRequestsGhost;

    event WithrawalFromTargets(
        address staker,
        address delegatedTo,
        address withdrawer,
        uint nonce,
        uint startBlock,
        IStrategy[] strategies,
        uint256[] shares
    );

    /// @notice queues withdrawals only for native ETH
    function operatorDelegator_queueWithdrawals(
        uint256 operatorDelegatorIndex,
        uint256 tokenAmounts
    ) public {
        OperatorDelegator operatorDelegator = OperatorDelegator(
            payable(address(_getRandomOperatorDelegator(operatorDelegatorIndex)))
        );

        uint256 nativeEthShares = uint256(
            eigenPodManager.podOwnerShares(address(operatorDelegator))
        );
        tokenAmounts = tokenAmounts % nativeEthShares;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(IS_NATIVE);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tokenAmounts;

        uint96 nonce = uint96(delegation.cumulativeWithdrawalsQueued(address(operatorDelegator)));
        // NOTE: this uses a simplification where only one collateral token type is queued for withdrawal at a time
        operatorDelegator.queueWithdrawals(tokens, amounts);

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(address(eigenPodManager.beaconChainETHStrategy())); // since only using native ETH in this case, strategy is from eigenPodManager
        // create and store the Withdrawal struct here because queueWithdrawals only returns a byte array
        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(operatorDelegator),
            delegatedTo: operatorDelegator.delegateAddress(),
            withdrawer: address(operatorDelegator),
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            shares: amounts
        });
        // emit WithrawalFromTargets(
        //     address(operatorDelegator),
        //     operatorDelegator.delegateAddress(),
        //     address(operatorDelegator),
        //     nonce,
        //     uint32(block.number),
        //     strategies,
        //     amounts
        // );

        eigenLayerWithdrawalRequestsGhost.push(withdrawal);
    }

    function operatorDelegator_completeQueuedWithdrawal(uint256 operatorDelegatorIndex) public {
        OperatorDelegator operatorDelegator = OperatorDelegator(
            payable(address(_getRandomOperatorDelegator(operatorDelegatorIndex)))
        );
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(IS_NATIVE);

        // need a withdrawal to be queued, grab the first one since queues are FIFO
        require(eigenLayerWithdrawalRequestsGhost.length > 0);
        IDelegationManager.Withdrawal memory withdrawal = eigenLayerWithdrawalRequestsGhost[0];

        vm.prank(address(operatorDelegator));
        try operatorDelegator.completeQueuedWithdrawal(withdrawal, tokens, 0) {} catch {
            t(false, "admin can't withdraw from EigenLayer");
        }
    }
}
