// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from "../lib/forge-std/src/Script.sol";
import {aur} from "../src/aur.sol";

contract DeployContract is Script {
    address public sender;
    /**
        @dev This funtion is setup in the script to deploy the contract
        @param "currencyAddress" this is the token address like "usdc, usdt"
        @param "amount" this is the amount per mounth to be provided by users
        @param "periods_claim" this var define the amount of periods for a user to claim the turn
     */
    function run(
        address currencyAddress,
        uint256 amount,
        uint16 periods_claim
    ) external returns (aur, address) {
        vm.startBroadcast();
        sender = msg.sender;
        aur ContactAur = new aur(currencyAddress, amount, periods_claim);
        vm.stopBroadcast();
        return (ContactAur, sender);
    }
}
