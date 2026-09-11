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
    error Natillera_MemberDoesNotExist(uint256);
    error Natillera_InvalidTurn(uint256);
    error Natillera_AllPeriods_Paid(uint256);
    error Natillera_NothingtoClaim(address);
    error Natillera_HasNot_Finished();

    ////////////////////////////
    ////// TYPE DECLARATIONS ///
    ////////////////////////////
    using SafeERC20 for IERC20;

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
    uint16 private s_periods_claim;
    uint256 private s_amount;
    uint256 private s_time;
    address private immutable s_moneyAddr;
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER");
    NatilleraStatus private s_natillera_status;

    mapping(uint64 period => uint256 colleted) private s_amount_colleted;
    mapping(uint64 period => uint256 colleted) private s_amount_late_colleted;
    mapping(uint256 id => uint256 amount_to_pay) private paying;

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
    /**
     * @dev This modifier checks that the member is up to date with their payments.
     * If the member is late (member_Status < 0) it reverts with a custom error.
     * @param id the id of the member to check
     */
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

    /**
     * @param _moneyAddr the address of the ERC20 token used for deposits
     * @param _amount the amount of tokens each member must deposit per period
     * @param _periods_claim the number of periods a member must wait before claiming their turn
     * @notice Initializes the natillera with the money token, the per-period amount and
     * the number of periods to claim. Grants the deployer the MEMBER_ROLE.
     * @dev Reverts if the money address is zero or if the amount/periods are zero.
     * The contract starts in the SETTING status.
     */
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
        if (member.LatestPeriod == (s_total_member * s_periods_claim)) {
            revert Natillera_AllPeriods_Paid(id);
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
        uint64 turn = s_members_turn[id];
        uint256 amountToWithdraw;
        (
            uint256 amountColleted,
            uint256 amountColletedLate
        ) = collected_forTurn(turn);

        if (member.pendingClaim == 0) {
            uint64 ActiveMembers = members_status();
            //check if all the memeber are active, if not it means that they will be pending money
            if ((ActiveMembers != s_total_member)) {
                //We don't have enough to pay
                uint256 pendingMoney = (
                    (s_amount * s_total_member * s_periods_claim)
                ) - (amountColleted + amountColletedLate);
                member.pendingClaim = pendingMoney;
            }
            amountToWithdraw = (amountColleted + amountColletedLate);
            clean_colleted_money(turn);
        } else {
            uint256 withdrawPending = member.pendingClaim;

            if (member.pendingClaim > amountColletedLate) {
                //We don't have enough to pay
                withdrawPending = amountColletedLate;
                member.pendingClaim = member.pendingClaim - amountColletedLate;
                clean_colleted_money(turn);
                //Clean amount colleted late
            } else {
                //Clean amount colleted late
                clean_colleted_money(turn);
                member.pendingClaim = 0;
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
     * @param newAdr the new address for the member
     * @notice this function is used to update a member's address
     * @dev this function checks that the caller is the smart contract associated
     * with the member. It revokes the role from the old address, updates the
     * member address and grants the role to the new address.
     */
    function updateMember(
        uint256 id,
        address newAdr
    ) external onlyRole(MEMBER_ROLE) {
        MemberData storage member = s_members_id[id];
        if (member.SmartContract != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (newAdr == address(0)) {
            revert Wallet_CantBeZero();
        }
        delete s_members_addr[member.addr];
        s_members_addr[newAdr] = id;
        _revokeRole(MEMBER_ROLE, member.addr);
        member.addr = newAdr;
        _grantRole(MEMBER_ROLE, newAdr);
    }
    /**
     * @notice this function is used to restart the natillera
     * @dev this function is currently a placeholder and does not perform any action
     */
    //we check if the periods have finish and if the majority ahave claim
    function reStart() external onlyRole(MEMBER_ROLE) {
        //make sure this funtion is not execute in twice
        //we get the active users number
        //we check howmuch money is in the contract
        //we transfert the money to those who hans't claim and they are on point
        //we imaging a situation where someone is not paying so he's not going to be able to claim
        // once the time has passed the money which has been collected and belongs
        // to his trun will be returned to those who were responsbale even if the money belongs
        // to whose who paid some periods and don't paid anymore, but the contract balance must be 0 after this
        if (
            ((((s_periods_claim * s_total_member) * 30 days) + s_time) +
                30 days) > block.timestamp
        ) {
            revert Natillera_HasNot_Finished();
        }
        uint256 ResponsableUsers = members_status();
        uint256 UnClaimedMoney;

        uint256 balanceContract = IERC20(s_moneyAddr).balanceOf(address(this));
        console.log("[reStart] ResponsableUsers=", ResponsableUsers);
        console.log("[reStart] balanceContract=", balanceContract);
        if (balanceContract > 0) {
            for (uint256 index = 0; index < membersId.length; index++) {
                MemberData memory member = s_members_id[membersId[index]];
                uint64 turn = s_members_turn[membersId[index]];
                int256 periodMember = member_Status(membersId[index]);

                if (periodMember >= 0) {
                    //user on time
                    //check if he has claimed, if not we transfert
                    (
                        uint256 amountColleted,
                        uint256 amountColletedLate
                    ) = collected_forTurn(turn);
                    console.log(
                        "[reStart]   collected=",
                        amountColleted,
                        "late=",
                        amountColletedLate
                    );

                    if (member.claim == true && member.pendingClaim > 0) {
                        // just the pendingmoney
                        paying[membersId[index]] += amountColletedLate;
                        UnClaimedMoney += amountColletedLate;
                    }
                    if (member.claim == false) {
                        paying[membersId[index]] += (amountColletedLate +
                            amountColleted);
                        UnClaimedMoney += (amountColletedLate + amountColleted);
                    }
                }
            }
            console.log("[reStart] UnClaimedMoney=", UnClaimedMoney);
            uint256 moneyToDistribute = (balanceContract - UnClaimedMoney) /
                ResponsableUsers;
            console.log("[reStart] moneyToDistribute=", moneyToDistribute);
            for (uint256 index = 0; index < membersId.length; index++) {
                int256 periodMember = member_Status(membersId[index]);
                if (periodMember >= 0) {
                    //user on time
                    paying[membersId[index]] += moneyToDistribute;
                    console.log(
                        "[reStart]   paying[",
                        membersId[index],
                        "]+=",
                        moneyToDistribute
                    );
                    console.log(
                        "[reStart]   paying[",
                        paying[membersId[index]],
                        "]+="
                    );
                }
            }
        }
        for (uint256 index = 0; index < membersId.length; index++) {
            MemberData storage member = s_members_id[membersId[index]];
            uint64 turn = s_members_turn[membersId[index]];
            clean_colleted_money(turn);
            member.LatestPeriod = 0;
            member.pendingClaim = 0;
            member.claim = false;
        }
        s_natillera_status = NatilleraStatus.SETTING;
    }
    function withdrawAfterContractFinished(
        uint256 id
    ) external onlyRole(MEMBER_ROLE) nonReentrant {
        //cheks
        MemberData storage member = s_members_id[id];
        if (member.addr != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (paying[id] == 0) {
            revert Natillera_NothingtoClaim(msg.sender);
        }
        //effects
        uint256 AmountWithdraw = paying[id];
        delete paying[id];
        //Interactions
        IERC20(s_moneyAddr).safeTransfer(msg.sender, AmountWithdraw);
    }

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
    ) external Natillera_Status_Started onlyRole(MEMBER_ROLE) {
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
        _grantRole(MEMBER_ROLE, smartContract);

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

    /**
     * @param id the id of the member whose turn is being changed
     * @param newTurn the new turn position (1-based) for the member
     * @notice this function moves a member to a new position in the turn order
     * @dev this function can only be called when the natillera is NOT started.
     * It validates the member exists and the new turn is within range, then
     * shifts the other members accordingly.
     */
    function ChangeTurn(
        uint256 id,
        uint256 newTurn
    ) external Natillera_Status_Started onlyRole(MEMBER_ROLE) {
        uint256 currentTurn = s_members_turn[id];

        if (currentTurn == 0) {
            revert Natillera_MemberDoesNotExist(id);
        }

        if (newTurn == 0 || newTurn > membersId.length) {
            revert Natillera_InvalidTurn(newTurn);
        }

        if (currentTurn == newTurn) {
            return;
        }

        uint256 currentIndex = currentTurn - 1;
        uint256 newIndex = newTurn - 1;

        // Mover hacia adelante
        if (newIndex < currentIndex) {
            for (uint256 i = currentIndex; i > newIndex; i--) {
                uint256 previousMember = membersId[i - 1];

                membersId[i] = previousMember;
                s_members_turn[previousMember] = uint64(i + 1);
            }
        }
        // Mover hacia atrás
        else {
            for (uint256 i = currentIndex; i < newIndex; i++) {
                uint256 nextMember = membersId[i + 1];

                membersId[i] = nextMember;
                s_members_turn[nextMember] = uint64(i + 1);
            }
        }

        membersId[newIndex] = id;
        s_members_turn[id] = uint64(newTurn);
    }
    /**
     * @param id the id of the member to delete
     * @notice this function deletes a member from the turn order
     * @dev this function can only be called when the natillera is NOT started.
     * It removes the member from the membersId array and shifts the remaining
     * members' turn positions.
     */
    function DeleteMember(
        uint256 id
    ) external Natillera_Status_Started onlyRole(MEMBER_ROLE) nonReentrant {
        //if user is about to be delete we send the money the have pending, notice that this is just if
        //the user has finished the first contract reponsibly
        //Cheks
        MemberData storage member = s_members_id[id];
        uint256 item = s_members_turn[id];
        if (item == 0) {
            revert Natillera_MemberDoesNotExist(id);
        }
        //Efects
        uint256 AmountWithdraw = paying[id];
        delete paying[id];
        for (uint256 index = item; index < membersId.length; index++) {
            membersId[index - 1] = membersId[index];
            s_members_turn[membersId[index - 1]] = uint64(index);
        }
        membersId.pop();
        delete s_members_addr[member.addr];
        _revokeRole(MEMBER_ROLE, member.addr);
        delete s_members_turn[id];
        delete s_members_id[id];
        //Interactions
        IERC20(s_moneyAddr).safeTransfer(msg.sender, AmountWithdraw);
    }

    //////////////////////////
    ////// VIEW FUNCTIONS ////
    //////////////////////////

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
    /**
     * @param turn the turn number of the member
     * @notice this function sums the collected amounts (on time and late) for
     * the periods that belong to a given turn
     * @dev this function computes the start and end period indexes for the turn
     * window and accumulates the collected amounts across those periods
     * @return total_Collated the total collected on time for the turn
     * @return total_Collated_Late the total collected late for the turn
     */
    function collected_forTurn(
        uint64 turn
    ) internal view returns (uint256, uint256) {
        uint256 total_Collated;
        uint256 total_Collated_Late;
        int64 startIndex = ((int64(turn) * int16(s_periods_claim)) - 1) + 1;
        int64 endIndex = (startIndex - (int16(s_periods_claim) - 1));

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
     * @param turn the turn number of the member
     * @notice this function zeroes out the late collected amounts for a turn
     * @dev this function computes the same period window as collected_forTurn
     * and resets the late collected amounts to zero
     */
    function clean_colleted_money(uint64 turn) internal {
        int64 startIndex = ((int64(turn) * int16(s_periods_claim)) - 1) + 1;
        int64 endIndex = (startIndex - (int16(s_periods_claim) - 1)) - 1;
        for (int64 index = startIndex; index >= endIndex; index--) {
            s_amount_late_colleted[uint64(index)] = 0;
            s_amount_colleted[uint64(index)] = 0;
        }
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
        if (period() > (s_periods_claim * s_total_member)) {
            s_period = (s_periods_claim * s_total_member);
        }
        MemberData memory member = s_members_id[id];
        int256 periods = int64(member.LatestPeriod) - int256(s_period);
        return periods;
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

    /**
     * @notice this function returns the current period of the natillera
     * @dev this function calculates the number of 30 day periods that have passed
     * since the natillera started
     * @return the current period number
     */
    function period() internal view returns (uint256) {
        return (block.timestamp - s_time) / (30 days);
    }

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
     * @dev this function is the external getter for the internal period() function
     * @return the current period number
     */
    function GetPeriod() external view returns (uint256) {
        return (period());
    }
    /**
     * @param id the id of the member to check
     * @notice this function returns the member status (how many periods ahead/behind)
     * @dev this function is the external getter for the internal member_Status() function
     * @return the member status as a signed integer
     */
    function Get_member_Status(uint256 id) external view returns (int256) {
        return member_Status(id);
    }
}
