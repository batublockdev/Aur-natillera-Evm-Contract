// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from "../lib/forge-std/src/Script.sol";
import {aur} from "../src/aur.sol";

contract DeployContract is Script {
    address public sender;

    function run() external returns (aur) {
        vm.startBroadcast();
        sender = msg.sender;
        aur ContactAur = new aur();
        vm.stopBroadcast();
        return (ContactAur);
    }
}
