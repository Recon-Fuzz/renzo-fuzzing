// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CryticAsserts } from "@chimera/CryticAsserts.sol";

import { RestakeManagerTargets } from "./RestakeManagerTargets.sol";
import { RestakeManagerAdminTargets } from "./RestakeManagerAdminTargets.sol";
import { DepositQueueTargets } from "./DepositQueueTargets.sol";

// echidna . --contract CryticTester --config echidna.yaml
// medusa fuzz
contract CryticTester is
    RestakeManagerTargets,
    RestakeManagerAdminTargets,
    DepositQueueTargets,
    CryticAsserts
{
    constructor() payable {
        setup();
    }
}
