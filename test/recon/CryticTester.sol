// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { RestakeManagerTargets } from "./RestakeManagerTargets.sol";
import { RestakeManagerAdminTargets } from "./RestakeManagerAdminTargets.sol";
import { CryticAsserts } from "@chimera/CryticAsserts.sol";

// echidna . --contract CryticTester --config echidna.yaml
// medusa fuzz
contract CryticTester is RestakeManagerTargets, RestakeManagerAdminTargets, CryticAsserts {
    constructor() payable {
        setup();
    }
}
