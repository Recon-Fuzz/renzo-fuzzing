// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CryticAsserts } from "@chimera/CryticAsserts.sol";

import { RestakeManagerTargets } from "./RestakeManagerTargets.sol";
import { WithdrawQueueTargets } from "./WithdrawQueueTargets.sol";
import { AdminTargets } from "./AdminTargets.sol";
import { DepositQueueTargets } from "./DepositQueueTargets.sol";
import { OperatorDelegatorTargets } from "./OperatorDelegatorTargets.sol";

// echidna . --contract CryticTester --config echidna.yaml
// medusa fuzz
contract CryticTester is
    RestakeManagerTargets,
    AdminTargets,
    DepositQueueTargets,
    WithdrawQueueTargets,
    OperatorDelegatorTargets,
    CryticAsserts
{
    constructor() payable {
        setup();
    }
}
