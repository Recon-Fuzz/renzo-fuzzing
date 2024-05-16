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

    function test_oracle_issue() public {
        // vm.warp(409965);
        restakeManager_deposit(
            46818479931335768769956719101053511583999650634856746494612028170762342270567,
            2835551612780900443140428457931978074665509452746564831934156413655086067869
        );
    }

    function test_sweepingERC20() public {
        restakeManager_depositTokenRewardsFromProtocol(200);
    }

    function test_stakeEthFromQueue() public {
        bytes memory pubkey = hex"123456";
        bytes memory signature = hex"789101";

        vm.deal(address(this), 40 ether);
        // send ETH to DepositQueue first
        (bool success, ) = address(depositQueue).call{ value: 33 ether }("");
        require(success, "Failed to send ether");

        restakeManager_stakeEthFromQueue(2, pubkey, signature, bytes32(uint256(0xbeef)));
    }

    function test_sweepERC20() public {
        // send tokens to DepositQueue first
        stETH.transfer(address(depositQueue), 200);

        restakeManager_depositTokenRewardsFromProtocol(2);
    }
}
