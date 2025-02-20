// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";

import { Setup } from "./Setup.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";

/// @notice this encompasses all admin permissions, not only the ones defined by the RESTAKE_MANAGER_ADMIN role in Renzo
abstract contract RestakeManagerAdminTargets is BaseTargetFunctions, Setup {
    function restakeManagerAdmin_setOperatorDelegatorAllocation(
        uint256 operatorDelegatorIndex,
        uint256 allocationBasisPoints
    ) public {
        IOperatorDelegator operatorDelegatorToUpdate = _getRandomOperatorDelegator(
            operatorDelegatorIndex
        );

        restakeManager.setOperatorDelegatorAllocation(
            operatorDelegatorToUpdate,
            allocationBasisPoints
        );
    }

    function restakeManagerAdmin_setPaused(bool paused) public {
        restakeManager.setPaused(paused);
    }

    function restakeManagerAdmin_setMaxDepositTVL(uint256 maxDeposit) public {
        restakeManager.setMaxDepositTVL(maxDeposit);
    }
}
