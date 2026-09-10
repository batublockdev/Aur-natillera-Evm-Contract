// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {aur} from "../../src/aur.sol";
import {ERC20Mock} from "../mock/ERC20Mock.sol";

/**
 * @title AUR Echidna Invariants
 * @notice Property-based fuzzing harness for the aur natillera contract.
 * @dev Echidna calls the echidna_* functions after every transaction sequence.
 * These must be view/pure and take no arguments.
 *
 * NOTE: This harness does NOT use Foundry cheatcodes (vm.*) because Echidna
 * does not provide them. Setup is done in the constructor using direct calls.
 */
contract AURInvariants {
    aur private aurContract;
    ERC20Mock private usdc;

    address private admin = address(0xAAAA);
    address private member1 = address(0x1111);
    address private member2 = address(0x2222);
    address private member3 = address(0x3333);

    constructor() {
        usdc = new ERC20Mock("USD DOLLAR", "USDC", 1000 ether, admin);
        usdc.mint(member1, 1000 ether);
        usdc.mint(member2, 1000 ether);
        usdc.mint(member3, 1000 ether);

        // Deploy as admin (constructor grants MEMBER_ROLE to msg.sender)
        aurContract = new aur(address(usdc), 10 ether, 3);

        // Add members (admin has MEMBER_ROLE from constructor)
        aurContract.addMember(1, member1, member1);
        aurContract.addMember(2, member2, member2);
        aurContract.addMember(3, member3, member3);

        // Approve
        usdc.approve(address(aurContract), type(uint256).max);

        // Start
        aurContract.startNatillera();
    }

    /**
     * @notice The contract should never hold more tokens than the total minted
     * to members (solvency-style bound).
     */
    function echidna_contract_balance_bounded() public view returns (bool) {
        return usdc.balanceOf(address(aurContract)) <= 3000 ether;
    }

    /**
     * @notice A member's pendingClaim should never exceed the total amount
     * that could be owed to them (amount * periods_claim).
     */
    function echidna_pending_claim_bounded() public view returns (bool) {
        (aur.MemberData memory m1, , ) = aurContract.getdataMember(1);
        (aur.MemberData memory m2, , ) = aurContract.getdataMember(2);
        (aur.MemberData memory m3, , ) = aurContract.getdataMember(3);
        uint256 maxOwed = 10 ether * 3; // amount * periods_claim
        return
            m1.pendingClaim <= maxOwed &&
            m2.pendingClaim <= maxOwed &&
            m3.pendingClaim <= maxOwed;
    }

    /**
     * @notice The total number of members should never exceed the number of
     * addMember calls (3 in setup).
     */
    function echidna_member_count_bounded() public view returns (bool) {
        (uint256 totalMember, , , , , , , ) = aurContract.getData();
        return totalMember <= 3;
    }
}
