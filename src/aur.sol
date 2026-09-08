// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {console} from "forge-std/console.sol";

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

////////////////////////////
////// IMPORTS /////////////
////////////////////////////
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/*
    @title aur
    @author batublockdev
    @notice This contract is a natillera contract which brings onchain the most commun saving mechanism in latin america.
     It allows a group of people to save money together and withdraw it in turns. The contract is designed to be used by 
     a group of people setting up the rules of the saving mechanism and decentralizing the process of saving money as a group. 
    @dev This contract is a work in progress and is not yet complete. It is not yet audited and should not be used in production.
*/

contract aur is AccessControl, ReentrancyGuard {
    ////////////////////////////
    ////// ERRORS //////////////
    ////////////////////////////
    error Wallet_CantBeZero();
    error Wallet_NotOwner();
    error Wallet_NotEnoughFunds();
    error Wallet__TokenNotValid(address token);
    error Wallet__NotApprovedForToken(address token);
    error Wallet__FaildReceiveToken(address token);
    error Wallet__SpenderNotValid(address spender);
    error Wallet_SignatureInvalid();
    error Wallet_TransferFailed();
    error Natillera_Status_Error(uint256 status);
    error Natillera_Member_Status_Late(uint256 id);
    error Natillera_Member_already_claim(address);
    error Natillera_Member_not_yourTurn(address);
    error Natillera_Wrong_Amount(uint256);
    error Natillera_Wrong_id(uint256);
    error Natillera_Wrong_address(address, address);
    error Natillera_Wrong_Doble_id(uint256);
    error Natillera_Wrong_Doble_Address(address);

    ////////////////////////////
    ////// TYPE DECLARATIONS ///
    ////////////////////////////
    using SafeERC20 for IERC20;
    enum MemberStatus {
        ACTIVE,
        INACTIVE
    }
    enum MemberTurn {
        WAITING,
        READY,
        DONE
    }
    enum NatilleraStatus {
        STARTED,
        PAUSED,
        SETTING
    }
    struct CheckClaim {
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }
    struct MemberData {
        uint256 id;
        address addr;
        address SmartContract;
        uint64 LatestPeriod;
        uint256 pendingClaim;
        bool claim;
    }

    ////////////////////////////
    ////// STATE VARIABLES /////
    ////////////////////////////
    uint256 private s_total_member;
    uint256 private s_amount_late;
    uint16 private s_periods_claim;
    uint256 private s_amount;
    uint256 private s_time;
    address private immutable s_moneyAddr;
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER");
    NatilleraStatus private s_natillera_status;

    mapping(uint64 period => uint256 colleted) private s_amount_colleted;
    mapping(uint64 period => uint256 colleted) private s_amount_late_colleted;

    mapping(uint256 => MemberData) private s_members_id;
    mapping(address addr => uint256 id) private s_members_addr;
    mapping(uint256 id => uint64 turn) private s_members_turn;
    uint256[] private membersId;

    ////////////////////////////
    ////// EVENTS //////////////
    ////////////////////////////

    ////////////////////////////
    ////// MODIFIERS ///////////
    ////////////////////////////
    /**
     * @dev This modifier checks the status of the Natillera.
     * If the status is PAUSED or SETTING, it reverts with a custom error.
     */
    modifier Natillera_Status() {
        if (
            s_natillera_status == NatilleraStatus.PAUSED ||
            s_natillera_status == NatilleraStatus.SETTING
        ) {
            revert Natillera_Status_Error(uint256(s_natillera_status));
        }
        _;
    }
    /**
     * @dev This modifier checks the status of the Natillera.
     * If the status is STARTED it reverts with a custom error.
     */
    modifier Natillera_Status_Started() {
        if (s_natillera_status == NatilleraStatus.STARTED) {
            revert Natillera_Status_Error(uint256(s_natillera_status));
        }
        _;
    }
    modifier Member_Status(uint256 id) {
        int256 periodMember = member_Status(id);
        if (periodMember < 0) {
            revert Natillera_Member_Status_Late(id);
        }

        _;
    }

    ////////////////////////////
    ////// FUNCTIONS ///////////
    ////////////////////////////

    ////////////////////////////
    ////// CONSTRUCTOR /////////
    ////////////////////////////
    //asinamos multas o no y cuanto es el porcentaje de multa
    //tenemos que setear el amount
    //29/30 =0.999 y el memeber period es 0, es decir casi terminamos el primer periodo y no ha pagado
    //29/30 =0.999 y el memeber period es 1, es decir aun casi terminamos el primer periodo y esta al dia
    //Miembros para estar al dia tienen  que estar adelante del periodo si es periodo 0, deben esta 1
    //si estan periodo 2 y member 0 se esta atrasado 2
    //Al menos establecer que miembro atrasado no recibe dinero
    // setear amount and periods to receive each member
    //we check if in the first periods the payments are not enough we declare  it inative
    constructor(address _moneyAddr, uint256 _amount, uint16 _periods_claim) {
        if (_moneyAddr == address(0)) {
            revert Natillera_Wrong_address(_moneyAddr, address(0));
        }
        if (_amount == 0 || _periods_claim == 0) {
            revert Wallet_CantBeZero();
        }
        s_moneyAddr = _moneyAddr;
        s_amount = _amount;
        s_natillera_status = NatilleraStatus.SETTING;
        s_periods_claim = _periods_claim;
        _grantRole(MEMBER_ROLE, msg.sender);
    }

    ////////////////////////////////
    ////// EXTERNAL FUNCTIONS //////
    ////////////////////////////////

    /**
     * @param id the id of the member making the deposit
     * @notice this function is used to deposit the token into the natillera
     * the member must have approved the contract to spend the token beforehand
     * @dev this function checks the natillera status, that the member exists,
     * that the amount is valid, that the allowance is enough and transfers
     * the tokens from the member to the contract. If the payment is late it
     * accumulates the amount into s_amount_late
     */
    function deposit_token(uint256 id) external Natillera_Status {
        MemberData storage member = s_members_id[id];
        if (member.addr == address(0)) {
            revert Wallet__SpenderNotValid(msg.sender);
        }

        if (
            IERC20(s_moneyAddr).allowance(msg.sender, address(this)) < s_amount
        ) {
            revert Wallet__NotApprovedForToken(s_moneyAddr);
        }
        IERC20(s_moneyAddr).safeTransferFrom(
            msg.sender,
            address(this),
            s_amount
        );

        //check if the payment has been done late
        //even to inform that payment has been done late
        int256 periodMember = member_Status(id);
        member.LatestPeriod++;

        if (periodMember < 0) {
            s_amount_late_colleted[member.LatestPeriod] += s_amount;
        } else {
            s_amount_colleted[member.LatestPeriod] += s_amount;
        }

        s_members_id[id] = member;
    }

    /**
     * @param newAmount the new amount to be deposited per period
     * @notice this function allows a member to change the amount of the natillera
     * @dev this function checks that the caller is a member and that the new amount is not zero
     */
    function changeAmount(
        uint256 newAmount
    ) external onlyRole(MEMBER_ROLE) Natillera_Status_Started {
        if (newAmount == 0) revert Wallet_CantBeZero();
        s_amount = newAmount;
    }
    /**
     * @param newPeriods the new number of periods each member has to wait to claim
     * @notice this function allows a member to change the number of periods to claim
     * @dev this function checks that the caller is a member and that the new periods are not zero
     */
    function changePeriods(
        uint16 newPeriods
    ) external onlyRole(MEMBER_ROLE) Natillera_Status_Started {
        if (newPeriods == 0) revert Wallet_CantBeZero();
        s_periods_claim = newPeriods;
    }
    //fix and add rentrancy and cheks so on ..
    // Need to susbtract pending from total amount late
    /**
     * @param id the id of the member claiming their turn
     * @notice this function allows a member to claim the money when it is their turn
     * @dev this function checks the member status, that the caller is the member,
     * that it is their turn and that they have not claimed before. It transfers
     * the corresponding amount or the pending amount if some members are inactive
     */
    function claim_myTurn(
        uint256 id
    ) external Member_Status(id) onlyRole(MEMBER_ROLE) nonReentrant {
        //Cheks
        MemberData storage member = s_members_id[id];
        if (member.addr != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        bool m_ismyturn = is_myTurn(id);
        if (m_ismyturn == false) {
            revert Natillera_Member_not_yourTurn(msg.sender);
        }
        if (member.claim == true) {
            if (member.pendingClaim == 0) {
                revert Natillera_Member_already_claim(msg.sender);
            }
        }
        //Effects
        uint256 amountToWithdraw;
        (
            uint256 amountColleted,
            uint256 amountColletedLate
        ) = collected_forTurn(s_members_turn[id]);

        if (member.pendingClaim == 0) {
            uint64 ActiveMembers = members_status();
            //check if all the memeber are active, if not it means that they will be pending money
            if ((ActiveMembers != s_total_member)) {
                //We don't have enough to pay
                console.log(
                    "[DBG] ActiveMembers=",
                    uint256(ActiveMembers),
                    "s_total=",
                    s_total_member
                );
                console.log("[DBG] amountColleted=", amountColleted);
                console.log(
                    "[DBG] s_amount*colleted*periods=",
                    s_amount * amountColleted * s_periods_claim
                );
                console.log(
                    "[DBG] s_amount*total*periods=",
                    s_amount * s_total_member * s_periods_claim
                );
                uint256 pendingMoney = ((s_amount *
                    s_total_member *
                    s_periods_claim) * 1 ether) - (amountColleted);
                member.pendingClaim = pendingMoney;
            }
            amountToWithdraw = amountColleted;
        } else {
            uint256 withdrawPending = member.pendingClaim;

            if (member.pendingClaim > amountColletedLate) {
                //We don't have enough to pay
                withdrawPending = amountColletedLate;
                member.pendingClaim = member.pendingClaim - amountColletedLate;
                //Clean amount colleted late
            } else {
                //Clean amount colleted late
            }
            amountToWithdraw = withdrawPending;
        }

        member.claim = true;
        s_members_id[id] = member;
        //Interactions
        IERC20(s_moneyAddr).safeTransfer(msg.sender, amountToWithdraw);
    }

    /**
     * @param id the id of the member to update
     * @notice this function is used to update a member
     * @dev this function checks that the caller is the smart contract associated
     * with the member. Currently it is a placeholder and does not perform any update
     */
    function updateMember(uint256 id) external {
        MemberData storage member = s_members_id[id];
        if (member.SmartContract != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        //here we need to gant the new one and delete the old address
    }
    /**
     * @notice this function is used to restart the natillera
     * @dev this function is currently a placeholder and does not perform any action
     */
    function reStart() external {}

    /**
     * @param id the id to assign to the new member
     * @param addr the address of the new member
     * @param smartContract the smart contract associated with the new member
     * @notice this function adds a new member to the natillera
     * @dev this function checks that the id and addresses are valid and not duplicated,
     * grants the MEMBER_ROLE, stores the member data and adds them to the turn order
     */
    function addMember(
        uint256 id,
        address addr,
        address smartContract
    ) external onlyRole(MEMBER_ROLE) {
        //need to prevent same id twice
        //Checks
        if (id == 0) {
            revert Natillera_Wrong_id(id);
        }
        if (addr == address(0) || smartContract == address(0)) {
            revert Natillera_Wrong_address(addr, smartContract);
        }
        if (s_members_addr[addr] != 0) {
            revert Natillera_Wrong_Doble_Address(addr);
        }
        if (s_members_turn[id] != 0) {
            revert Natillera_Wrong_Doble_id(id);
        }
        // EFFECTS
        _grantRole(MEMBER_ROLE, addr);
        s_members_id[id] = MemberData({
            id: id,
            addr: addr,
            SmartContract: smartContract,
            LatestPeriod: 0,
            pendingClaim: 0,
            claim: false
        });
        s_members_addr[addr] = id;
        s_total_member++;
        s_members_turn[id] = uint64(s_total_member);
        membersId.push(id);
    }
    /**
     * @notice this function starts the natillera
     * @dev this function sets the start time and changes the status to STARTED
     */
    function startNatillera()
        external
        onlyRole(MEMBER_ROLE)
        Natillera_Status_Started
    {
        s_time = block.timestamp;
        s_natillera_status = NatilleraStatus.STARTED;
    }

    //80% thresold
    //80% thresold
    /**
     * @notice this function is used to delete a member
     * @dev this function is currently a placeholder and does not perform any action
     */
    function deleteMember() external {
        // we need to remove grant role
    }

    ///////////////////////////////
    ////// INTERNAL FUNCTIONS //////
    ///////////////////////////////

    //we check member status
    //member no active can't withdraw
    //so if there are just
    //if we got
    /**
     * @notice this function counts how many members are currently active
     * (not late on their payments)
     * @dev this function iterates over all the members and returns the number
     * of those whose member_Status is >= 0 (up to date)
     * @return numberActiveMember the amount of active members
     */
    function members_status() internal view returns (uint64) {
        uint64 numberActiveMember;

        for (uint256 index = 0; index < membersId.length; index++) {
            int256 periodMember = member_Status(membersId[index]);
            if (periodMember >= 0) {
                numberActiveMember++;
            }
        }
        return numberActiveMember;
    }
    function collected_forTurn(
        uint64 turn
    ) internal view returns (uint256, uint256) {
        uint256 total_Collated;
        uint256 total_Collated_Late;
        int64 startIndex = ((int64(turn) * int16(s_periods_claim)) - 1) + 1;
        int64 endIndex = (startIndex - (int16(s_periods_claim) - 1)) - 1;

        console.log("[DBG] turn=", uint256(turn));
        console.log("[DBG] periods=", uint256(s_periods_claim));
        console.log("[DBG] startIndex=", uint256(uint64(startIndex)));
        console.log("[DBG] endIndex=", uint256(uint64(endIndex)));
        for (int64 index = startIndex; index >= endIndex; index--) {
            console.log("[DBG] loop index=", uint256(uint64(index)));
            total_Collated += s_amount_colleted[uint64(index)];
            total_Collated_Late += s_amount_late_colleted[uint64(index)];
        }
        return (total_Collated, total_Collated_Late);
    }

    /**
     * @param id the id of the member to check
     * @notice this function returns how many periods a member is behind or ahead
     * @dev this function compares the current period with the member's LatestPeriod
     * a negative result means the member is late
     * @return periods the difference between the current period and the member's latest period
     */
    function member_Status(uint256 id) internal view returns (int256) {
        uint256 s_period = period();
        MemberData memory member = s_members_id[id];
        int256 periods = int64(member.LatestPeriod) - int256(s_period);
        return periods;
    }

    /**
    This are changes whihc are going to be available during the setting state
    to restart or start we need to make sure all memeber agree so we need 100% signs

    deleteMember()
changeRules()
changeAmount()
changePeriods()
changeTurns()
cancelNatillera()
emergencyWithdraw() 
        enum action_id {
        deleteMember?,
        changeAmount,
        changePeriods,
        changeTurns?,
        emergencyWithdraw
    }
    struct CheckClaim {
        uint18 Action_identifier;
        address spender/membertoEliminate/x;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }*/

    //We need a rebase token to check the turns
    //We need to verify members
    //Each member will have a turn number 1, 2 , 3 .. and can be apply each 3 periods
    //so if memeber x has turn 2 we check if we are in period 6 or if already pass that on so he can access to the money
    //we need a also a track to avoid doble claiming
    // we need a funtion to restar values like period and claim+
    //We want this to happen in a especific order because of the birthdays
    //otherwise we need to add a ramdoness feature can be from chainlink
    /**
     * @param item the index from which the turn order will be shifted
     * @notice this function removes a member from the turn order and shifts
     * the remaining members one position up
     * @dev this function is used internally when a member is deleted or changes turn
     */
    function setTurnOrder(uint256 item) internal {
        for (uint256 index = item; index > membersId.length - 1; index++) {
            membersId[index] = membersId[index + 1];
            // s_members_turn[membersId[index + 1]] = index + 1;
        }
        membersId.pop();
    }
    /**
     * @param id the id of the member whose turn is going to change
     * @param newTurn the new turn position for the member
     * @notice this function changes the turn of a member in the order
     * @dev this function is internal and shifts the turn order accordingly
     */
    function changeTurns(uint256 id, uint256 newTurn) internal {
        uint256 item = s_members_turn[id];
        item--;
        setTurnOrder(item);
    }
    /**
     * @param id the id of the member to delete
     * @notice this function deletes a member from the turn order
     * @dev this function is internal and removes the member from the order
     */
    function DeleteMember(uint256 id) internal {
        uint256 item = s_members_turn[id];
        item--;
        setTurnOrder(item);
    }

    /**
     * @param id the id of the member to check
     * @notice this function checks if it is the turn of a member to claim
     * @dev this function checks the member status, that the member has not claimed
     * before and that the current period is within the member's turn window
     * @return ismyturn true if it is the member's turn, false otherwise
     */
    function is_myTurn(
        uint256 id
    ) internal view Member_Status(id) returns (bool) {
        uint256 turn = s_members_turn[id];
        uint256 s_period = period();
        bool ismyturn = false;
        if (s_period >= (s_periods_claim * turn)) {
            ismyturn = true;
        }
        return ismyturn;
    }

    //////////////////////////
    ////// VIEW FUNCTIONS ////
    //////////////////////////
    /**
     * @param id the id of the member to check
     * @notice this function is the external version of is_myTurn
     * @dev this function exposes the is_myTurn check to external callers
     * @return turn true if it is the member's turn, false otherwise
     */
    function is_myTurn_ext(uint256 id) external view returns (bool) {
        bool turn = is_myTurn(id);
        return turn;
    }
    /**
     * @notice this function returns the main data of the natillera
     * @dev this function returns the total members, late amount, periods to claim,
     * amount, start time, money token address, status and the list of member ids
     * @return the total members, late amount, periods to claim, amount, start time,
     * money token address, status and member ids
     */
    function getData()
        external
        view
        returns (
            uint256,
            uint256,
            uint16,
            uint256,
            uint256,
            address,
            uint256,
            uint256[] memory,
            uint64
        )
    {
        return (
            s_total_member,
            s_amount_late,
            s_periods_claim,
            s_amount,
            s_time,
            s_moneyAddr,
            uint256(s_natillera_status),
            membersId,
            members_status()
        );
    }
    /**
     * @param id the id of the member to get the data from
     * @notice this function returns the data of a specific member
     * @dev this function returns the member data, their turn and their index
     * @return the member data, the turn and the index of the member
     */
    function getdataMember(
        uint256 id
    ) external view returns (MemberData memory, uint256, uint256) {
        MemberData memory member = s_members_id[id];
        uint256 turn = s_members_turn[id];
        uint256 idx = s_members_addr[member.addr];

        return (member, turn, idx);
    }
    /**
     * @notice this function returns the current period of the natillera
     * @dev this function calculates the number of 30 day periods that have passed
     * since the natillera started
     * @return the current period number
     */
    function period() internal view returns (uint256) {
        return (block.timestamp - s_time) / (30 days);
    }
    function GetPeriod() external view returns (uint256) {
        return (period());
    }
    function Get_member_Status(uint256 id) external view returns (int256) {
        return member_Status(id);
    }
}
