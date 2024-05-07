// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { RestakeManagerTargets } from "./RestakeManagerTargets.sol";
import { FoundryAsserts } from "@chimera/FoundryAsserts.sol";

contract CryticToFoundry is Test, RestakeManagerTargets, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function testDemo() public {
        console2.log("restake manager: ", address(restakeManager));
    }
}
