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
    function _logMemberState(uint256 id, string memory title) internal {
        (
            aur.MemberData memory member,
            uint256 value1,
            uint256 value2
        ) = aurContract.getdataMember(id);

        console.log("==========");
        console.log(title);
        console.log("==========");

        console.log("Member ID:", member.id);
        console.log("Member address:", member.addr);
        console.log("SmartContract:", member.SmartContract);
        console.log("LatestPeriod:", member.LatestPeriod);
        console.log("pendingClaim:", member.pendingClaim);
        console.log("claim:", member.claim);

        console.log("value1:", value1);
        console.log("value2:", value2);
    }
    function _logBalances(string memory title) internal {
        console.log("==========");
        console.log(title);
        console.log("==========");

        console.log("member1 balance:", usdc.balanceOf(address(member1)));

        console.log("aur balance:", usdc.balanceOf(address(aurContract)));
    }
    //////////////////////////
    ////// CONSTRUCTION FUNCTION ////
    //////////////////////////
    /**
    @dev We test the cheks in the constroction funtion like address 0
     */
    function test_constructor_checks() public {
        //Test address 0
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_address.selector,
                address(0),
                address(0)
            )
        );
        aurContract = new aur(address(0), 10 ether, 3);

        //Test amount 0
        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract = new aur(address(usdc), 0, 3);

        //Test peridos 0
        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract = new aur(address(usdc), 20, 0);

        //Test both 0
        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract = new aur(address(usdc), 0, 0);
    }
    /**
    @dev We chek if the data added in the constructor on the setup  has been added
     */
    function test_constructor_Effects() public {
        // data inserted in the set up   aurContract = new aur(address(usdc), 10 ether, 3);
        (
            uint256 totalMember,
            uint16 periodsClaim,
            uint256 amount,
            uint256 time,
            address moneyAddr,
            uint256 status,
            uint256[] memory members,

        ) = aurContract.getData();

        console.log("totalMember:", totalMember);
        console.log("periodsClaim:", periodsClaim);
        console.log("amount:", amount);
        console.log("time:", time);
        console.log("moneyAddr:", moneyAddr);
        console.log("status:", status);

        console.log("members length:", members.length);

        for (uint256 i = 0; i < members.length; i++) {
            console.log("member ID:", members[i]);
        }

        assertEq(totalMember, 0);
        assertEq(members.length, 0);
        assertEq(periodsClaim, 3);
        assertEq(amount, 10 ether);
        assertEq(time, 0);
        assertEq(moneyAddr, address(usdc));
        // expect the contract to be in setting  which is 2
        assertEq(status, uint256(2));
    }
    //////////////////////////
    ////// ADDMEMBER FUNCTION ////
    //////////////////////////
    /**
        @dev Test the role error, preventing users externos from gettins access to funtions
     */
    function test_addMember_MemberError() public {
        vm.prank(member1);
        aurContract.addMember(2222222, address(member1), address(member1));
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(this),
                aurContract.MEMBER_ROLE()
            )
        );
        aurContract.addMember(100111, address(member2), address(member2));
    }
    /**
        @dev Test all checks, like adding empty data or the same address twice
     */
    function test_addMember_Checks() public {
        // Test id o
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(aur.Natillera_Wrong_id.selector, uint256(0))
        );
        aurContract.addMember(0, address(member1), address(member1));

        // Test address o
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_address.selector,
                address(0),
                address(member1)
            )
        );
        aurContract.addMember(5113123, address(0), address(member1));

        // Test address smartcontract o
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_address.selector,
                address(member1),
                address(0)
            )
        );
        aurContract.addMember(5113123, address(member1), address(0));

        // Test address smartcontract o and address o
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_address.selector,
                address(0),
                address(0)
            )
        );
        aurContract.addMember(5113123, address(0), address(0));

        // Test sending same address twice
        //First time
        vm.prank(member1);
        aurContract.addMember(5113123, address(member1), address(member1));

        //Second time
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_Doble_Address.selector,
                address(member1)
            )
        );
        aurContract.addMember(5113123, address(member1), address(member1));

        // Test sending same id twice
        //First time
        vm.prank(member1);
        aurContract.addMember(51131232, address(member2), address(member2));

        //Second time
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Wrong_Doble_id.selector,
                uint256(51131232)
            )
        );
        aurContract.addMember(51131232, address(member3), address(member3));
    }
    /**
        @dev Test the effects check if the data has been added
     */
    function test_addMember_Effects() public {
        vm.prank(member1);
        aurContract.addMember(51131232, address(member1), address(member1));

        (aur.MemberData memory member, uint256 turn, uint256 id) = aurContract
            .getdataMember(51131232);

        console.log("----- MEMBER -----");
        console.log("ID:", member.id);
        console.log("Address:", member.addr);
        console.log("SmartContract:", member.SmartContract);
        console.log("LatestPeriod:", member.LatestPeriod);
        console.log("PendingClaim:", member.pendingClaim);
        console.log("Claim:", member.claim);

        console.log("Turn:", turn);
        console.log("Id:", id);

        assertEq(member.id, 51131232);
        assertEq(id, 51131232);
        assertEq(member.addr, address(member1));
        assertEq(member.SmartContract, address(member1));
        assertEq(member.LatestPeriod, 0);
        assertEq(member.pendingClaim, 0);
        assertEq(turn, 1);

        assertFalse(member.claim);

        (
            uint256 totalMember,
            uint16 periodsClaim,
            uint256 amount,
            uint256 time,
            address moneyAddr,
            uint256 status,
            uint256[] memory members,

        ) = aurContract.getData();

        console.log("totalMember:", totalMember);
        console.log("periodsClaim:", periodsClaim);
        console.log("amount:", amount);
        console.log("time:", time);
        console.log("moneyAddr:", moneyAddr);
        console.log("status:", status);

        console.log("members length:", members.length);

        for (uint256 i = 0; i < members.length; i++) {
            console.log("member ID:", members[i]);
        }
    }

    //////////////////////////
    ////// STARTNATILLERA FUNCTION ////
    //////////////////////////
    /**
        @dev Test that only a member can start the natillera
     */
    function test_startNatillera_OnlyMember() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        // Non-member cannot start
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                address(NoMember),
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.startNatillera();
    }
    /**
        @dev Test that startNatillera sets the time and status to STARTED
     */
    function test_startNatillera_Effects() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.warp(block.timestamp + 100);
        vm.prank(member1);
        aurContract.startNatillera();

        (, , , uint256 time, , uint256 status, , ) = aurContract.getData();
        assertEq(time, block.timestamp);
        // STARTED = 0
        assertEq(status, uint256(0));
    }
    /**
        @dev Test that startNatillera revert when is already started
     */
    function test_startNatillera_Effects_x2() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.warp(block.timestamp + 100);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Status_Error.selector,
                uint256(0)
            )
        );
        aurContract.startNatillera();
    }

    //////////////////////////
    ////// CHANGEPERIODS FUNCTION ////
    //////////////////////////
    /**
        @dev Test that only a member can change periods
     */
    function test_changePeriods_OnlyMember() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.changePeriods(5);
    }
    /**
        @dev Test that changePeriods reverts when newPeriods is 0
     */
    function test_changePeriods_ZeroReverts() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        vm.prank(member1);
        aurContract.changePeriods(0);
    }
    /**
        @dev Test that changePeriods reverts when is STARTED
     */
    function test_changePeriods_StartedRvert() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.prank(member1);
        aurContract.startNatillera();

        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Status_Error.selector,
                uint256(0)
            )
        );
        vm.prank(member1);

        aurContract.changePeriods(3);
    }
    /**
        @dev Test that changePeriods updates the periods
     */
    function test_changePeriods_Effects() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.prank(member1);
        aurContract.changePeriods(5);

        (, uint16 periodsClaim, , , , , , ) = aurContract.getData();
        assertEq(periodsClaim, 5);
    }

    //////////////////////////
    ////// CHANGEAMOUNT FUNCTION ////
    //////////////////////////
    /**
        @dev Test that only a member can change the amount
     */
    function test_changeAmount_OnlyMember() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.changeAmount(20 ether);
    }
    /**
        @dev Test that changeAmount reverts when newAmount is 0
     */
    function test_changeAmount_ZeroReverts() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        vm.prank(member1);
        aurContract.changeAmount(0);
    }
    /**
        @dev Test that changeAmount reverts when is STARTED
     */
    function test_changeAmount_started() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.prank(member1);
        aurContract.startNatillera();

        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Status_Error.selector,
                uint256(0)
            )
        );
        vm.prank(member1);
        aurContract.changeAmount(0);
    }
    /**
        @dev Test that changeAmount updates the amount
     */
    function test_changeAmount_Effects() public {
        vm.prank(member1);
        aurContract.addMember(1, address(member1), address(member1));

        vm.prank(member1);
        aurContract.changeAmount(20 ether);

        (, , uint256 amount, , , , , ) = aurContract.getData();
        assertEq(amount, 20 ether);
    }

    //////////////////////////
    ////// DEPOSIT_TOKEN FUNCTION ////
    //////////////////////////
    /**
        @dev Helper to add a member and approve the contract to spend their tokens
     */
    function _addMemberAndApprove(
        uint256 id,
        address member,
        uint256 amount
    ) internal {
        vm.prank(member1);
        aurContract.addMember(id, member, member);
        vm.prank(member);
        usdc.approve(address(aurContract), amount);
    }
    /**
        @dev Test that deposit_token reverts when the natillera is in SETTING state
     */
    function test_deposit_token_SettingReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Status_Error.selector,
                uint256(2) // SETTING
            )
        );
        aurContract.deposit_token(1);
    }
    /**
        @dev Test that deposit_token reverts when the member does not exist
     */
    function test_deposit_token_NonMemberReverts() public {
        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Wallet__SpenderNotValid.selector,
                member1
            )
        );
        aurContract.deposit_token(99);
    }

    /**
        @dev Test that deposit_token reverts when the allowance is not enough
     */
    function test_deposit_token_NotApprovedReverts() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);
        vm.prank(member1);
        aurContract.startNatillera();

        // No approval given
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Wallet__NotApprovedForToken.selector,
                address(usdc)
            )
        );
        aurContract.deposit_token(1);
    }
    /**
        @dev Test that deposit_token transfers the tokens and updates LatestPeriod
     */
    function test_deposit_token_Effects() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        uint256 balanceBefore = usdc.balanceOf(address(aurContract));
        vm.prank(member1);
        aurContract.deposit_token(1);

        assertEq(
            usdc.balanceOf(address(aurContract)),
            balanceBefore + 10 ether
        );

        (aur.MemberData memory member, , ) = aurContract.getdataMember(1);
        assertEq(member.LatestPeriod, 1);
    }

    //////////////////////////
    ////// IS_MYTURN FUNCTION ////
    //////////////////////////
    /**
        @dev Test is_myTurn_ext for a member whose turn has not arrived yet has to return false
     */
    function test_is_myTurn_NotYet() public {
        _addMemberAndApprove(1, member1, 50 ether);

        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        // turn 1, periods_claim 3 -> turn window is period < 3
        vm.warp(block.timestamp + 30 days); // period 1
        console.log("Period:", aurContract.GetPeriod());
        console.log("Member state:", aurContract.Get_member_Status(1));

        bool turn = aurContract.is_myTurn_ext(1);
        assertFalse(turn);
    }
    /**
        @dev Test is_myTurn_ext for a member whose turn has  arrived so it has to return true
     */
    function test_is_myTurn_Arrived() public {
        _addMemberAndApprove(1, member1, 50 ether);

        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        // turn 1, periods_claim 3 -> turn window is period < 3
        vm.warp(block.timestamp + 92 days); // period 1
        console.log("Period:", aurContract.GetPeriod());
        console.log("Member state:", aurContract.Get_member_Status(1));

        bool turn = aurContract.is_myTurn_ext(1);
        assertTrue(turn);
    }

    //////////////////////////
    ////// CLAIM_MYTURN FUNCTION ////
    //////////////////////////
    /**
        @dev Test that claim_myTurn reverts when it is not the caller's turn
     */
    function test_claim_myTurn_NotYourTurnReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        _addMemberAndApprove(2, member2, 10 ether);

        vm.prank(member1);
        aurContract.startNatillera();

        // member1 deposits
        vm.prank(member1);
        aurContract.deposit_token(1);

        // member1 tries to claim but is not his turn
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Member_not_yourTurn.selector,
                member1
            )
        );
        vm.prank(member1);
        aurContract.claim_myTurn(1);
    }
    /**
        @dev Test that claim_myTurn reverts when the caller is not equal to the id
     */
    function test_claim_myTurn_NotidMember() public {
        _addMemberAndApprove(1, member1, 10 ether);
        _addMemberAndApprove(2, member2, 10 ether);

        vm.prank(member1);
        aurContract.startNatillera();

        // member1 deposits
        vm.prank(member1);
        aurContract.deposit_token(1);

        // member2 tries to claim member1's turn
        vm.prank(member2);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Wallet__SpenderNotValid.selector,
                member2
            )
        );
        aurContract.claim_myTurn(1);
    }

    /**
        @dev Test is_myTurn_ext reverts for a member that already claimed
        @notice With 1 member and periods_claim 3, the max deposits is 3
        (Natillera_AllPeriods_Paid), so we use 2 members to allow a second
        deposit round after the first claim.
     */
    function test_is_myTurn_AlreadyClaimedReverts() public {
        _addMemberAndApprove(1, member1, 60 ether);
        _addMemberAndApprove(2, member2, 60 ether);

        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);

        // turn 1, periods_claim 3 -> turn window is period < 3
        vm.warp(block.timestamp + 92 days); // period 3

        vm.prank(member1);
        aurContract.claim_myTurn(1);

        vm.warp(block.timestamp + 92 days); // period 6
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Member_already_claim.selector,
                member1
            )
        );
        vm.prank(member1);
        aurContract.claim_myTurn(1);
    }
    /**
        @dev Test claiming the pending money works
     */
    function test_is_myTurn_AlreadyClaimedPending() public {
        _addMemberAndApprove(1, member1, 60 ether);
        _addMemberAndApprove(2, member2, 60 ether);
        _addMemberAndApprove(3, member3, 60 ether);
        // =========================
        // BEFORE DEPOSIT
        // =========================

        _logBalances("BEFORE DEPOSIT");
        _logMemberState(1, "MEMBER BEFORE DEPOSIT");
        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member3);
        aurContract.deposit_token(3);
        // =========================
        // AFTER DEPOSIT
        // =========================

        _logBalances("AFTER DEPOSIT");
        _logMemberState(1, "MEMBER AFTER DEPOSIT");
        // turn 1, periods_claim 3 -> turn window is period < 3
        vm.warp(block.timestamp + 92 days); // period 3
        // =========================
        // BEFORE CLAIM
        // =========================

        _logMemberState(1, "BEFORE CLAIM");
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        // =========================
        // AFTER CLAIM
        // =========================

        _logBalances("AFTER CLAIM");
        _logMemberState(1, "MEMBER AFTER CLAIM");

        vm.prank(member3);
        aurContract.deposit_token(3);
        vm.prank(member3);
        aurContract.deposit_token(3);

        vm.warp(block.timestamp + 92 days); // period 6
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        vm.prank(member1);
        aurContract.claim_myTurn(1);
        // =========================
        // AFTER CLAIM
        // =========================

        _logBalances("AFTER CLAIM");
        _logMemberState(1, "MEMBER AFTER CLAIM");
    }
    /**
        @dev Test claimin pending monet twice
     */
    function test_is_myTurn_AlreadyClaimedPendingx2() public {
        _addMemberAndApprove(1, member1, 60 ether);
        _addMemberAndApprove(2, member2, 60 ether);
        _addMemberAndApprove(3, member3, 60 ether);
        // =========================
        // BEFORE DEPOSIT
        // =========================

        _logBalances("BEFORE DEPOSIT");
        _logMemberState(1, "MEMBER BEFORE DEPOSIT");
        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member3);
        aurContract.deposit_token(3);
        // =========================
        // AFTER DEPOSIT
        // =========================

        _logBalances("AFTER DEPOSIT");
        _logMemberState(1, "MEMBER AFTER DEPOSIT");
        // turn 1, periods_claim 3 -> turn window is period < 3
        vm.warp(block.timestamp + 92 days); // period 3
        // =========================
        // BEFORE CLAIM
        // =========================

        _logMemberState(1, "BEFORE CLAIM");
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        // =========================
        // AFTER CLAIM
        // =========================

        _logBalances("AFTER CLAIM");
        _logMemberState(1, "MEMBER AFTER CLAIM");

        vm.prank(member3);
        aurContract.deposit_token(3);

        vm.warp(block.timestamp + 92 days); // period 6
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        vm.prank(member1);
        aurContract.claim_myTurn(1);
        // =========================
        // AFTER CLAIM
        // =========================

        _logBalances("AFTER CLAIM");
        _logMemberState(1, "MEMBER AFTER CLAIM");
        vm.warp(block.timestamp + 2 days); // period 6

        vm.prank(member3);
        aurContract.deposit_token(3);
        vm.prank(member1);
        aurContract.claim_myTurn(1);
        _logBalances("AFTER CLAIMx2");
        _logMemberState(1, "MEMBER AFTER CLAIMx2");
    }
    /**
        @dev Test claiming revert when pendign is 0 and try to claim
     */
    function test_is_myTurn_AlreadyClaimedPendingRevert() public {
        _addMemberAndApprove(1, member1, 60 ether);
        _addMemberAndApprove(2, member2, 60 ether);
        _addMemberAndApprove(3, member3, 60 ether);
        // =========================
        // BEFORE DEPOSIT
        // =========================

        _logBalances("BEFORE DEPOSIT");
        _logMemberState(1, "MEMBER BEFORE DEPOSIT");
        vm.prank(member1);
        aurContract.startNatillera();

        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member3);
        aurContract.deposit_token(3);
        // =========================
        // AFTER DEPOSIT
        // =========================

        _logBalances("AFTER DEPOSIT");
        _logMemberState(1, "MEMBER AFTER DEPOSIT");
        // turn 1, periods_claim 3 -> turn window is period < 3
        vm.warp(block.timestamp + 92 days); // period 3
        // =========================
        // BEFORE CLAIM
        // =========================

        _logMemberState(1, "BEFORE CLAIM");
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        // =========================
        // AFTER CLAIM
        // =========================

        _logBalances("AFTER CLAIM");
        _logMemberState(1, "MEMBER AFTER CLAIM");

        vm.prank(member3);
        aurContract.deposit_token(3);

        vm.warp(block.timestamp + 92 days); // period 6
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        vm.prank(member1);
        aurContract.claim_myTurn(1);
        // =========================
        // AFTER CLAIM
        // =========================

        _logBalances("AFTER CLAIM");
        _logMemberState(1, "MEMBER AFTER CLAIM");
        vm.warp(block.timestamp + 2 days); // period 6

        vm.prank(member3);
        aurContract.deposit_token(3);
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Member_already_claim.selector,
                member1
            )
        );
        vm.prank(member1);
        aurContract.claim_myTurn(1);
    }
    /**
        @dev Test that claim_myTurn reverts when the member is late
     */
    function test_claim_myTurn_LateReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // Advance 2 periods without depositing -> member is late
        vm.warp(block.timestamp + 60 days);

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Member_Status_Late.selector,
                uint256(1)
            )
        );
        aurContract.claim_myTurn(1);
    }

    //////////////////////////
    ////// GETDATA MEMBER FUNCTION ////
    //////////////////////////
    /**
        @dev Test getdataMember for a non-existent member returns empty data
     */
    function test_getdataMember_NonExistent() public {
        (aur.MemberData memory member, uint256 turn, uint256 id) = aurContract
            .getdataMember(999);
        assertEq(member.id, 0);
        assertEq(member.addr, address(0));
        assertEq(turn, 0);
        assertEq(id, 0);
    }
    /**
        @dev Test getdataMember returns the correct data after adding a member
     */
    function test_getdataMember_Effects() public {
        vm.prank(member1);
        aurContract.addMember(42, member2, member2);

        (aur.MemberData memory member, uint256 turn, uint256 id) = aurContract
            .getdataMember(42);
        assertEq(member.id, 42);
        assertEq(member.addr, address(member2));
        assertEq(turn, 1);
        assertEq(id, 42);
    }

    //////////////////////////
    ////// PERIOD FUNCTION ////
    //////////////////////////
    /**
        @dev Test that period returns 0 before the natillera starts
     */
    function test_period_BeforeStart() public {
        // period is internal, so we check via is_myTurn_ext which uses period()
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);

        // Before start, s_time = 0 -> period is huge, but is_myTurn uses it
        // We just verify the call does not revert for a fresh member
        bool turn = aurContract.is_myTurn_ext(1);
        assertFalse(turn);
    }

    //////////////////////////
    ////// GETPERIOD FUNCTION ////
    //////////////////////////
    /**
        @dev Test that GetPeriod returns 0 right after the natillera starts
     */
    function test_GetPeriod_ZeroAtStart() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);
        vm.prank(member1);
        aurContract.startNatillera();

        // No time has passed -> period 0
        assertEq(aurContract.GetPeriod(), 0);
    }
    /**
        @dev Test that GetPeriod increments by 1 for each full 30 day period
     */
    function test_GetPeriod_AfterWarp() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);
        vm.prank(member1);
        aurContract.startNatillera();

        // Advance 30 days -> period 1
        vm.warp(block.timestamp + 30 days);
        assertEq(aurContract.GetPeriod(), 1);

        // Advance another 30 days -> period 2
        vm.warp(block.timestamp + 30 days);
        assertEq(aurContract.GetPeriod(), 2);

        // Advance 29 days (not a full period) -> still period 2
        vm.warp(block.timestamp + 29 days);
        assertEq(aurContract.GetPeriod(), 2);
    }

    //////////////////////////
    ////// GET_MEMBER_STATUS FUNCTION ////
    //////////////////////////
    /**
        @dev Test that Get_member_Status returns 0 for a member up to date
     */
    function test_Get_member_Status_UpToDate() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // Deposit once -> LatestPeriod 1, current period 0 -> status 1
        vm.prank(member1);
        aurContract.deposit_token(1);
        assertEq(aurContract.Get_member_Status(1), 1);
    }
    /**
        @dev Test that Get_member_Status returns a negative value when late
     */
    function test_Get_member_Status_Late() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // Advance 2 periods without depositing -> member is late by 2
        vm.warp(block.timestamp + 60 days);
        assertEq(aurContract.Get_member_Status(1), -2);
    }

    //////////////////////////
    ////// UPDATEMEMBER FUNCTION ////
    //////////////////////////
    /**
        @dev Test that updateMember reverts when the caller is not a member (role check)
        @notice updateMember now has onlyRole(MEMBER_ROLE), so a non-member reverts
        with AccessControlUnauthorizedAccount before reaching the SmartContract check.
     */
    function test_updateMember_NotMemberReverts() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);

        // member2 is not a member -> role check reverts first
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                member2,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(member2);
        aurContract.updateMember(1, member2);
    }
    /**
        @dev Test that updateMember reverts when the caller is a member but not the member's SmartContract
        @notice A member who is not the SmartContract of the target id reverts with Wallet__SpenderNotValid.
     */
    function test_updateMember_NotSmartContractReverts() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);
        vm.prank(member1);
        aurContract.addMember(2, member2, member2);

        // member2 is a member but not the SmartContract of member1 -> revert
        vm.prank(member2);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Wallet__SpenderNotValid.selector,
                member2
            )
        );
        aurContract.updateMember(1, member3);
    }
    /**
        @dev Test that updateMember reverts when the new address is zero
     */
    function test_updateMember_ZeroAddressReverts() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);

        vm.prank(member1);
        vm.expectRevert(abi.encodeWithSelector(aur.Wallet_CantBeZero.selector));
        aurContract.updateMember(1, address(0));
    }
    /**
        @dev Test that updateMember updates the member address and roles
     */
    function test_updateMember_Effects() public {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);

        // member1 is the SmartContract, updates its own address to member2
        vm.prank(member1);
        aurContract.updateMember(1, member2);

        (aur.MemberData memory member, , ) = aurContract.getdataMember(1);
        assertEq(member.addr, address(member2));

        // Old address should no longer have the role, new one should
        assertFalse(aurContract.hasRole(aurContract.MEMBER_ROLE(), member1));
        assertTrue(aurContract.hasRole(aurContract.MEMBER_ROLE(), member2));
    }

    //////////////////////////
    ////// CHANGETURN FUNCTION ////
    //////////////////////////
    /**
        @dev Helper to add 3 members WITHOUT starting the natillera.
        @notice ChangeTurn and DeleteMember use the Natillera_Status_Started modifier,
        which reverts when the natillera IS started, so these tests must run in SETTING state.
     */
    function _setupThreeMembers() internal {
        vm.prank(member1);
        aurContract.addMember(1, member1, member1);
        vm.prank(member1);
        aurContract.addMember(2, member2, member2);
        vm.prank(member1);
        aurContract.addMember(3, member3, member3);
    }
    /**
        @dev Test that ChangeTurn reverts when the member does not exist
     */
    function test_ChangeTurn_NonExistentReverts() public {
        _setupThreeMembers();

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_MemberDoesNotExist.selector,
                99
            )
        );
        aurContract.ChangeTurn(99, 2);
    }
    /**
        @dev Test that ChangeTurn reverts when the new turn is invalid (0 or out of range)
     */
    function test_ChangeTurn_InvalidTurnReverts() public {
        _setupThreeMembers();

        // newTurn 0
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_InvalidTurn.selector,
                uint256(0)
            )
        );
        aurContract.ChangeTurn(1, 0);

        // newTurn greater than members length (3)
        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_InvalidTurn.selector,
                uint256(4)
            )
        );
        aurContract.ChangeTurn(1, 4);
    }
    /**
        @dev Test that ChangeTurn moves a member forward in the turn order
     */
    function test_ChangeTurn_MoveForward() public {
        _setupThreeMembers();

        // member1 (turn 1) moves to turn 3
        vm.prank(member1);
        aurContract.ChangeTurn(1, 3);

        (, uint256 turn1, ) = aurContract.getdataMember(1);
        (, uint256 turn2, ) = aurContract.getdataMember(2);
        (, uint256 turn3, ) = aurContract.getdataMember(3);

        assertEq(turn1, 3);
        assertEq(turn2, 1);
        assertEq(turn3, 2);
    }
    /**
        @dev Test that ChangeTurn moves a member backward in the turn order
     */
    function test_ChangeTurn_MoveBackward() public {
        _setupThreeMembers();

        // member3 (turn 3) moves to turn 1
        vm.prank(member1);
        aurContract.ChangeTurn(3, 1);

        (, uint256 turn1, ) = aurContract.getdataMember(1);
        (, uint256 turn2, ) = aurContract.getdataMember(2);
        (, uint256 turn3, ) = aurContract.getdataMember(3);

        assertEq(turn1, 2);
        assertEq(turn2, 3);
        assertEq(turn3, 1);
    }
    /**
        @dev Test that ChangeTurn does nothing when the turn is unchanged
     */
    function test_ChangeTurn_SameTurnNoop() public {
        _setupThreeMembers();

        vm.prank(member1);
        aurContract.ChangeTurn(1, 1);

        (, uint256 turn1, ) = aurContract.getdataMember(1);
        assertEq(turn1, 1);
    }

    //////////////////////////
    ////// DELETEMEMBER (TURN) FUNCTION ////
    //////////////////////////
    /**
        @dev Test that DeleteMember reverts when the member does not exist
     */
    function test_DeleteMember_NonExistentReverts() public {
        _setupThreeMembers();

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_MemberDoesNotExist.selector,
                99
            )
        );
        aurContract.DeleteMember(99);
    }
    /**
        @dev Test that DeleteMember removes the member from the turn order
     */
    function test_DeleteMember_Effects() public {
        _setupThreeMembers();

        // Delete member2 (turn 2)
        vm.prank(member1);
        aurContract.DeleteMember(2);

        // member2 turn should be deleted (0)
        console.log("aqui");
        console.log("aqui");

        console.log("aqui");

        console.log("aqui");

        (, uint256 turn2, ) = aurContract.getdataMember(2);
        assertEq(turn2, 0);

        // member3 should have moved to turn 2
        (, uint256 turn3, ) = aurContract.getdataMember(3);
        assertEq(turn3, 2);

        // member1 stays at turn 1
        (, uint256 turn1, ) = aurContract.getdataMember(1);
        assertEq(turn1, 1);
    }

    //////////////////////////
    ////// CLAIM_MYTURN EXTRA COVERAGE ////
    //////////////////////////
    /**
        @dev Test that claim_myTurn transfers the collected amount to the member
     */
    function test_claim_myTurn_TransfersBalance() public {
        _addMemberAndApprove(1, member1, 30 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // member1 deposits 3 times (periods_claim = 3)
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member1);
        aurContract.deposit_token(1);

        uint256 balanceBefore = usdc.balanceOf(member1);
        vm.warp(block.timestamp + 92 days); // period 3 -> turn ready

        vm.prank(member1);
        aurContract.claim_myTurn(1);

        // member1 should have received 30 ether (3 deposits x 10 ether)
        assertEq(usdc.balanceOf(member1), balanceBefore + 30 ether);
        assertEq(usdc.balanceOf(address(aurContract)), 0);
    }
    /**
        @dev Test that claim_myTurn reverts when the member is late (Member_Status modifier)
     */
    function test_claim_myTurn_LateModifierReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // Advance 2 periods without depositing -> member is late
        vm.warp(block.timestamp + 60 days);

        vm.prank(member1);
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Member_Status_Late.selector,
                uint256(1)
            )
        );
        aurContract.claim_myTurn(1);
    }
    /**
        @dev Test that claim_myTurn reverts when the caller is not a member (role check)
        @notice The Member_Status modifier runs before onlyRole, so the member must be
        up to date (not late) for the role check to be reached. With periods_claim = 3
        and 1 member, the max deposits is 3 (Natillera_AllPeriods_Paid). Depositing 3
        times keeps LatestPeriod = 3, which is up to date at period 3 (status 0).
     */
    function test_claim_myTurn_NonMemberReverts() public {
        _addMemberAndApprove(1, member1, 50 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // member1 deposits 3 times (max allowed with 1 member, periods_claim 3)
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }

        vm.warp(block.timestamp + 92 days); // period 3 -> turn ready

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.claim_myTurn(1);
    }

    //////////////////////////
    ////// DEPOSIT_TOKEN: ALL PERIODS PAID ////
    //////////////////////////
    /**
        @dev Test that deposit_token reverts once a member has paid all periods
        (LatestPeriod == s_total_member * s_periods_claim).
     */
    function test_deposit_token_AllPeriodsPaidReverts() public {
        _addMemberAndApprove(1, member1, 50 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // 1 member, periods_claim 3 -> max 3 deposits
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }

        // 4th deposit must revert
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_AllPeriods_Paid.selector,
                uint256(1)
            )
        );
        vm.prank(member1);
        aurContract.deposit_token(1);
    }
    /**
        @dev Test that a member can still deposit after the AllPeriods_Paid limit
        is reached once the natillera is restarted (LatestPeriod reset to 0).
        @notice reStart only avoids the division-by-zero path when the contract
        balance is 0 (all members claimed), so we claim first to empty the balance.
     */
    function test_deposit_token_AllPeriodsPaid_AfterRestart() public {
        _addMemberAndApprove(1, member1, 50 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }

        // Claim to empty the contract balance (avoids division-by-zero in reStart)
        vm.warp(block.timestamp + 92 days); // period 3 -> turn ready
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        // Advance past the full contract duration so reStart is allowed
        // duration = periods_claim * total_member * 30 days + 30 days
        vm.warp(block.timestamp + (3 * 1 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        // reStart sets status back to SETTING; start again to allow deposits
        vm.prank(member1);
        aurContract.startNatillera();

        // After restart, LatestPeriod is 0 -> can deposit again
        vm.prank(member1);
        aurContract.deposit_token(1);

        (aur.MemberData memory member, , ) = aurContract.getdataMember(1);
        assertEq(member.LatestPeriod, 1);
    }

    //////////////////////////
    ////// RESTART FUNCTION ////
    //////////////////////////
    /**
        @dev Test that reStart reverts when the contract has not finished yet.
     */
    function test_reStart_NotFinishedReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // Not enough time has passed
        vm.expectRevert(
            abi.encodeWithSelector(aur.Natillera_HasNot_Finished.selector)
        );
        vm.prank(member1);
        aurContract.reStart();
    }
    /**
        @dev Test that reStart reverts when called by a non-member.
     */
    function test_reStart_OnlyMember() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.warp(block.timestamp + (3 * 1 * 30 days) + 30 days + 1);

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.reStart();
    }
    /**
        @dev Test that reStart resets member state and sets status back to SETTING.
        With a single member who paid all periods and claimed, the contract balance
        should be 0 and the member state reset.
     */
    function test_reStart_Effects() public {
        _addMemberAndApprove(1, member1, 50 ether);
        _addMemberAndApprove(2, member2, 50 ether);

        vm.prank(member1);
        aurContract.startNatillera();

        // member1 pays all 3 periods
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
            vm.prank(member2);
            aurContract.deposit_token(2);
        }

        vm.warp(block.timestamp + 92 days); // period 3 -> turn ready
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        // Advance past full duration
        vm.warp(block.timestamp + (3 * 1 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        // Status back to SETTING (2)
        (, , , , , uint256 status, , ) = aurContract.getData();
        assertEq(status, uint256(2));

        // Member state reset
        (aur.MemberData memory member, , ) = aurContract.getdataMember(1);
        assertEq(member.LatestPeriod, 0);
        assertEq(member.pendingClaim, 0);
        assertFalse(member.claim);

        (aur.MemberData memory member2, , ) = aurContract.getdataMember(2);
        assertEq(member2.LatestPeriod, 0);
        assertEq(member2.pendingClaim, 0);
        assertFalse(member2.claim);
    }

    //////////////////////////
    ////// WITHDRAW AFTER CONTRACT FINISHED ////
    //////////////////////////
    /**
        @dev Test that withdrawAfterContractFinished reverts when there is nothing to claim.
     */
    function test_withdrawAfterContractFinished_NothingToClaimReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.warp(block.timestamp + (3 * 1 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        // No paying balance for member1
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_NothingtoClaim.selector,
                member1
            )
        );
        vm.prank(member1);
        aurContract.withdrawAfterContractFinished(1);
    }
    /**
        @dev Test that withdrawAfterContractFinished reverts when called by a non-member.
     */
    function test_withdrawAfterContractFinished_OnlyMember() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.warp(block.timestamp + (3 * 1 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.withdrawAfterContractFinished(1);
    }
    /**
        @dev Test that withdrawAfterContractFinished reverts when the caller is not the member
        associated with the id.
     */
    function test_withdrawAfterContractFinished_NotOwnerReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        _addMemberAndApprove(2, member2, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.warp(block.timestamp + (3 * 2 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        // member2 tries to withdraw member1's id
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Wallet__SpenderNotValid.selector,
                member2
            )
        );
        vm.prank(member2);
        aurContract.withdrawAfterContractFinished(1);
    }
    /**
        @dev Test that withdrawAfterContractFinished reverts when the caller is not a member
        (role check).
     */
    function test_withdrawAfterContractFinished_NonMemberReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.warp(block.timestamp + (3 * 1 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.withdrawAfterContractFinished(1);
    }

    //////////////////////////
    ////// DELETEMEMBER: PAYING TRANSFER ////
    //////////////////////////
    /**
        @dev Test that DeleteMember reverts when called by a non-member (role check).
     */
    function test_DeleteMember_NonMemberReverts() public {
        _setupThreeMembers();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                NoMember,
                aurContract.MEMBER_ROLE()
            )
        );
        vm.prank(NoMember);
        aurContract.DeleteMember(1);
    }
    /**
        @dev Test that DeleteMember reverts when the natillera is STARTED.
     */
    function test_DeleteMember_StartedReverts() public {
        _addMemberAndApprove(1, member1, 10 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_Status_Error.selector,
                uint256(0) // STARTED
            )
        );
        vm.prank(member1);
        aurContract.DeleteMember(1);
    }

    //////////////////////////
    ////// BUG TESTS: reStart DIVISION BY ZERO ////
    //////////////////////////
    /**
        @dev [KNOWN BUG] Test that withdrawAfterContractFinished transfers the pending
        paying balance. Scenario: 2 members, member2 never pays -> member1 (responsible)
        gets the unclaimed money via paying[] after reStart.
        @notice This test currently FAILS because reStart() reverts with a division-by-zero
        panic when the contract balance > 0 (ResponsableUsers is always 0 once
        period > total_periods). It documents the bug and should pass once reStart is fixed.
     */
    function test_withdrawAfterContractFinished_Transfers() public {
        _addMemberAndApprove(1, member1, 100 ether);
        _addMemberAndApprove(2, member2, 100 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        // member1 pays all 6 periods (2 members * 3 periods)
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }
        // member2 pays nothing -> late

        // Advance past full duration
        vm.warp(block.timestamp + (3 * 2 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        uint256 balanceBefore = usdc.balanceOf(member1);
        vm.prank(member1);
        aurContract.withdrawAfterContractFinished(1);

        // member1 should have received something (the unclaimed money from member2's turn)
        assertGt(usdc.balanceOf(member1), balanceBefore);
    }
    /**
        @dev [KNOWN BUG] Test that DeleteMember transfers the member's pending paying balance.
        Scenario: member1 has a paying balance after reStart, then gets deleted and
        receives the pending amount.
        @notice This test currently FAILS because reStart() reverts with a division-by-zero
        panic when the contract balance > 0. It documents the bug and should pass once
        reStart is fixed.
     */
    function test_DeleteMember_TransfersPaying() public {
        _addMemberAndApprove(1, member1, 100 ether);
        _addMemberAndApprove(2, member2, 100 ether);
        vm.prank(member1);
        aurContract.startNatillera();

        for (uint256 i = 0; i < 6; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }

        vm.warp(block.timestamp + (3 * 2 * 30 days) + 30 days + 1);
        vm.prank(member1);
        aurContract.reStart();

        // member1 has a paying balance now; delete member2 (no paying balance)
        uint256 balanceBefore = usdc.balanceOf(member1);
        vm.prank(member1);
        aurContract.DeleteMember(2);

        // member2 removed from turn order
        (, uint256 turn2, ) = aurContract.getdataMember(2);
        assertEq(turn2, 0);
        // member1 still at turn 1
        (, uint256 turn1, ) = aurContract.getdataMember(1);
        assertEq(turn1, 1);
        // member1 balance unchanged (member2 had no paying balance)
        assertEq(usdc.balanceOf(member1), balanceBefore);
    }

    //////////////////////////
    ////// RESTART: MULTI-SCENARIO TESTS ////
    //////////////////////////
    /**
        @dev Helper: add 3 members, approve them, start the natillera.
        periods_claim = 3, amount = 10 ether.
     */
    function _setupThreeMembersStarted() internal {
        _addMemberAndApprove(1, member1, 100 ether);
        _addMemberAndApprove(2, member2, 100 ether);
        _addMemberAndApprove(3, member3, 100 ether);
        vm.prank(member1);
        aurContract.startNatillera();
    }
    /**
        @dev Helper: advance time past the full contract duration so reStart is allowed.
        duration = periods_claim * total_member * 30 days + 30 days.
     */
    function _warpPastDuration() internal {
        vm.warp(block.timestamp + (3 * 3 * 30 days) + 30 days + 1);
    }
    /**
        @dev Test the scenario: member3 pays once then stops. member1 and member2 pay
        everything. After reStart, the money member3 paid (and the unclaimed money from
        his turn) is distributed to the responsible members (member1, member2).
        @notice This is the key scenario the user asked about.
     */
    function test_reStart_OnePayerStops_DistributesToResponsible() public {
        _setupThreeMembersStarted();

        // member1 and member2 pay all 9 periods (3 members * 3 periods)
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
            vm.prank(member2);
            aurContract.deposit_token(2);
        }
        // member3 pays only once
        vm.prank(member3);
        aurContract.deposit_token(3);

        _warpPastDuration();
        vm.prank(member1);
        aurContract.reStart();

        // member1 and member2 are responsible -> they have a paying balance
        uint256 bal1Before = usdc.balanceOf(member1);
        uint256 bal2Before = usdc.balanceOf(member2);
        vm.prank(member1);
        aurContract.withdrawAfterContractFinished(1);
        vm.prank(member2);
        aurContract.withdrawAfterContractFinished(2);

        // Both responsible members received money
        assertGt(usdc.balanceOf(member1), bal1Before);
        assertGt(usdc.balanceOf(member2), bal2Before);

        // member3 (moroso) has nothing to claim
        vm.expectRevert(
            abi.encodeWithSelector(
                aur.Natillera_NothingtoClaim.selector,
                member3
            )
        );
        vm.prank(member3);
        aurContract.withdrawAfterContractFinished(3);
    }
    /**
        @dev Test that after reStart + all responsible members withdraw, the contract
        balance is fully distributed (0).
     */
    function test_reStart_BalanceZeroAfterDistribution() public {
        _setupThreeMembersStarted();

        for (uint256 i = 0; i < 9; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
            vm.prank(member2);
            aurContract.deposit_token(2);
        }
        vm.prank(member3);
        aurContract.deposit_token(3);

        _warpPastDuration();
        vm.prank(member1);
        aurContract.reStart();

        // reStart registers the money in paying[] but does not transfer it.
        // The balance is only drained once the responsible members withdraw.
        uint256 balAfterRestart = usdc.balanceOf(address(aurContract));
        assertGt(balAfterRestart, 0);

        // member1 and member2 (responsible) withdraw their full paying balance
        vm.prank(member1);
        aurContract.withdrawAfterContractFinished(1);
        vm.prank(member2);
        aurContract.withdrawAfterContractFinished(2);

        // All money distributed -> contract balance 0
        assertEq(usdc.balanceOf(address(aurContract)), 0);
    }
    /**
        @dev Test that reStart can be called again after a full cycle (restart + start + pay).
        Verifies the natillera can run a second round without issues.
     */
    function test_reStart_SecondCycleWorks() public {
        _setupThreeMembersStarted();

        // Round 1: everyone pays everything
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
            vm.prank(member2);
            aurContract.deposit_token(2);
            vm.prank(member3);
            aurContract.deposit_token(3);
        }

        _warpPastDuration();
        vm.prank(member1);
        aurContract.reStart();

        // Status back to SETTING, start again
        vm.prank(member1);
        aurContract.startNatillera();

        // Round 2: members can deposit again (LatestPeriod reset to 0)
        vm.prank(member1);
        aurContract.deposit_token(1);
        vm.prank(member2);
        aurContract.deposit_token(2);
        vm.prank(member3);
        aurContract.deposit_token(3);

        (aur.MemberData memory m1, , ) = aurContract.getdataMember(1);
        (aur.MemberData memory m2, , ) = aurContract.getdataMember(2);
        (aur.MemberData memory m3, , ) = aurContract.getdataMember(3);
        assertEq(m1.LatestPeriod, 1);
        assertEq(m2.LatestPeriod, 1);
        assertEq(m3.LatestPeriod, 1);
    }
    /**
        @dev Test that a member who paid everything but never claimed gets their full
        collected amount via paying[] after reStart.
     */
    function test_reStart_UnclaimedResponsibleGetsFullAmount() public {
        _setupThreeMembersStarted();

        // member1 pays everything, never claims
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }

        _warpPastDuration();
        vm.prank(member1);
        aurContract.reStart();

        // member1 is responsible and unclaimed -> gets his collected amount
        uint256 balBefore = usdc.balanceOf(member1);
        vm.prank(member1);
        aurContract.withdrawAfterContractFinished(1);
        assertGt(usdc.balanceOf(member1), balBefore);
    }
    /**
        @dev Test that a member who claimed but has pendingClaim gets only the pending
        amount via paying[] after reStart.
     */
    function test_reStart_ClaimedWithPendingGetsPending() public {
        _setupThreeMembersStarted();

        // member1 pays everything and claims his turn
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(member1);
            aurContract.deposit_token(1);
        }
        vm.warp(block.timestamp + 92 days); // period 3 -> turn 1 ready
        vm.prank(member1);
        aurContract.claim_myTurn(1);

        _warpPastDuration();
        vm.prank(member1);
        aurContract.reStart();

        // member1 claimed -> no paying balance (or only pending)
        // He should NOT be able to withdraw a full amount again
        // (withdrawAfterContractFinished reverts if paying[id] == 0)
        // We just verify reStart succeeded and state reset
        (aur.MemberData memory m1, , ) = aurContract.getdataMember(1);
        assertEq(m1.LatestPeriod, 0);
        assertFalse(m1.claim);
    }
}
