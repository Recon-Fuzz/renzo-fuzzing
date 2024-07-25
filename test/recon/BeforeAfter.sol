// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { Setup } from "./Setup.sol";
import { WithdrawQueueStorageV1 } from "../../contracts/Withdraw/WithdrawQueueStorage.sol";
import { console2 } from "forge-std/console2.sol";

abstract contract BeforeAfter is Setup {
    struct Vars {
        uint256 totalTVL;
    }

    Vars internal _before;
    Vars internal _after;

    function __before() internal {
        (, , uint256 totalTVL) = restakeManager.calculateTVLs();
        _before.totalTVL = totalTVL;
    }

    function __after() internal {
        (, , uint256 totalTVL) = restakeManager.calculateTVLs();
        _after.totalTVL = totalTVL;
    }
}
