// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseSetup } from "@chimera/BaseSetup.sol";
import { RenzoSetup } from "test/RenzoSetup.sol";

abstract contract Setup is RenzoSetup, BaseSetup {
    function setup() internal virtual override {
        // calling RenzoSetup::setUp to deploy the renzo system, this includes deploying a local version of EigenLayer
        setUp();
    }
}
