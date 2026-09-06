//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {aur} from "../src/aur.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {DeployContract} from "../script/aurDeploy.s.sol";

contract RebaseTokenTest is Test {
    //USERS
    address public member1 = makeAddr("member1");
    address public member2 = makeAddr("member2");
    address public member3 = makeAddr("member3");
    address public member4 = makeAddr("member4");
    address public member5 = makeAddr("member5");

    ERC20Mock usdc;
    uint256 public loanId;

    aur private aurContract;
    DeployContract deploy;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    function setUp() public {
        usdc = new ERC20Mock("USD DOLLAR", "USDC", 100 ether, member1);
        usdc.mint(member2, 100 ether);
        usdc.mint(member3, 100 ether);
        usdc.mint(member4, 100 ether);
        usdc.mint(member5, 100 ether);

        deploy = new DeployContract();
        (aurContract) = deploy.run(address(usdc), 10 ether, 3);

        // Set up the mock ERC20 token
    }
}
