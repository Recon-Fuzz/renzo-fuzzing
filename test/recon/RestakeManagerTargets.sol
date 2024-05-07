// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { BeforeAfter } from "./BeforeAfter.sol";
import { Properties } from "./Properties.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";

abstract contract RestakeManagerTargets is BaseTargetFunctions, Properties, BeforeAfter {
    function restakeManager_deposit(IERC20 collateralToken, uint256 amount) public {
        restakeManager.deposit(collateralToken, amount);
    }

    function restakeManager_depositReferral(
        IERC20 collateralToken,
        uint256 amount,
        uint256 referralId
    ) public {
        restakeManager.deposit(collateralToken, amount, referralId);
    }

    function restakeManager_depositETH() public payable {
        restakeManager.depositETH();
    }

    function restakeManager_depositETHReferral(uint256 referralId) public payable {
        restakeManager.depositETH(referralId);
    }
}
