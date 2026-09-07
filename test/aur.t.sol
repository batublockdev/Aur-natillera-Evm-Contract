//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {aur} from "../src/aur.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {DeployContract} from "../script/aurDeploy.s.sol";
import {console} from "../lib/forge-std/src/console.sol";
contract aurTest is Test {
    //USERS
    address public member1 = makeAddr("member1");
    address public member2 = makeAddr("member2");
    address public member3 = makeAddr("member3");
    address public member4 = makeAddr("member4");
    address public member5 = makeAddr("member5");
    address public NoMember = makeAddr("memberx");

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
        vm.prank(member1);
        aurContract = new aur(address(usdc), 10 ether, 3);
    }
    /**
        @dev test addmember funtion
     */
    function test_addMember() public {
        vm.prank(member1);
        aurContract.addMember(2222222, address(member1), address(member1));
        aurContract.addMember(100111, address(member2), address(member2));
    }
}
