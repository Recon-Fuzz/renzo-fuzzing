// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { RestakeManagerTargetsV2 } from "./RestakeManagerTargetsV2.sol";
import { FoundryAsserts } from "@chimera/FoundryAsserts.sol";

contract CryticToFoundryV2 is Test, RestakeManagerTargetsV2, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_target_deployer() public {
        restakeManager_deployTokenStratOperatorDelegator();
    }
}
