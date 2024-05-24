// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { RestakeManagerTargetsV2 } from "./RestakeManagerTargetsV2.sol";
import { RestakeManagerAdminTargetsV2 } from "./RestakeManagerAdminTargetsV2.sol";
import { DepositQueueTargetsV2 } from "./DepositQueueTargetsV2.sol";
import { CryticAsserts } from "@chimera/CryticAsserts.sol";

// echidna . --contract CryticTester --config echidna.yaml
// medusa fuzz
contract CryticTesterV2 is
    RestakeManagerTargetsV2,
    RestakeManagerAdminTargetsV2,
    DepositQueueTargetsV2,
    CryticAsserts
{
    constructor() payable {
        setup();
    }
}
