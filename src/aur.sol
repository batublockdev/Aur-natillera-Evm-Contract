// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

//imports
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
/*
    @title aur
    @author batublockdev
    @notice This contract is a natillera contract which brings onchain the most commun saving mechanism in latin america.
     It allows a group of people to save money together and withdraw it in turns. The contract is designed to be used by 
     a group of people setting up the rules of the saving mechanism and decentralizing the process of saving money as a group. 
    @dev This contract is a work in progress and is not yet complete. It is not yet audited and should not be used in production.
*/

contract aur is AccessControl {
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

    uint256 private s_total_member;
    uint256 private s_amount_late;
    uint16 private s_periods_claim;
    uint256 private s_amount;
    uint256 private s_time;
    address private immutable s_moneyAddr;
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER");
    NatilleraStatus private s_natillera_status;

    mapping(uint256 => MemberData) private s_members_id;
    mapping(address addr => uint256 id) private s_members_addr;
    mapping(uint256 id => uint256 turn) private s_members_turn;
    uint256[] private membersId;

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
        uint256 LatestPeriod;
        uint256 pendingClaim;
        bool claim;
    }
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
    modifier Member_Status(uint256 id) {
        int256 periodMember = member_Status(id);
        if (periodMember < 0) {
            revert Natillera_Member_Status_Late(id);
        }

        _;
    }
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
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        s_moneyAddr = _moneyAddr;
        s_amount = _amount;
        s_natillera_status = NatilleraStatus.SETTING;
        s_periods_claim = _periods_claim;
    }

    ////////////////////////////////
    ////// EXTERNAL FUNCTIONS //////
    ////////////////////////////////

    fallback() external payable {
        this.deposit();
    }

    receive() external payable {
        this.deposit();
    }

    //No required verification
    function deposit() external payable {}

    function deposit_token(
        uint256 amount,
        uint256 id
    ) external Natillera_Status {
        MemberData storage member = s_members_id[id];
        if (member.addr == address(0)) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (amount == 0 || amount < s_amount)
            revert Natillera_Wrong_Amount(amount);
        if (IERC20(s_moneyAddr).allowance(msg.sender, address(this)) < amount) {
            revert Wallet__NotApprovedForToken(s_moneyAddr);
        }
        if (
            IERC20(s_moneyAddr).transferFrom(
                msg.sender,
                address(this),
                amount
            ) == false
        ) {
            revert Wallet__FaildReceiveToken(s_moneyAddr);
        }
        //check if the payment has been done late
        //even to inform that payment has been done late
        int256 periodMember = member_Status(id);
        if (periodMember < 0) {
            s_amount_late += amount;
        }

        member.LatestPeriod++;
        s_members_id[id] = member;
    }

    //we check member status
    //member no active can't withdraw
    //so if there are just
    //if we got
    function members_status() internal view returns (uint64) {
        uint64 numberActiveMember;
        for (uint256 index = 0; index > membersId.length; index++) {
            int256 periodMember = member_Status(membersId[index]);
            if (periodMember >= 0) {
                numberActiveMember++;
            }
        }
        return numberActiveMember;
    }
    function member_Status(uint256 id) internal view returns (int256) {
        uint256 s_period = period();
        MemberData memory member = s_members_id[id];
        int256 periods = int256(s_period) - int256(member.LatestPeriod);
        return periods;
    }
    function is_myTurn_ext(uint256 id) external view returns (bool) {
        bool turn = is_myTurn(id);
        return turn;
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
    function setTurnOrder(uint256 item) internal {
        for (uint256 index = item; index > membersId.length - 1; index++) {
            membersId[index] = membersId[index + 1];
            s_members_turn[membersId[index + 1]] = index + 1;
        }
        membersId.pop();
    }
    function changeAmount(uint256 newAmount) external onlyRole(MEMBER_ROLE) {
        uint256 id = s_members_addr[msg.sender];
        if (id == 0) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (newAmount == 0) revert Wallet_CantBeZero();
        s_amount = newAmount;
    }
    function changePeriods(uint16 newPeriods) external onlyRole(MEMBER_ROLE) {
        uint256 id = s_members_addr[msg.sender];
        if (id == 0) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (newPeriods == 0) revert Wallet_CantBeZero();
        s_periods_claim = newPeriods;
    }
    function changeTurns(uint256 id, uint256 newTurn) internal {
        uint256 item = s_members_turn[id];
        item--;
        setTurnOrder(item);
    }
    function DeleteMember(uint256 id) internal {
        uint256 item = s_members_turn[id];
        item--;
        setTurnOrder(item);
    }
    function claim_myTurn(uint256 id) external Member_Status(id) {
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
                revert Wallet__SpenderNotValid(msg.sender);
            }
        }

        //We must make sure perios to calim is not 0 also amou

        if (member.pendingClaim == 0) {
            uint64 ActiveMembers = members_status();
            //check if all the memeber are active, if not it means that they will be pending money
            if ((ActiveMembers != s_total_member)) {
                //no tenemos lo suficiente para pagar
                uint256 pendingMoney = (s_amount *
                    s_total_member *
                    s_periods_claim) -
                    (s_amount * ActiveMembers * s_periods_claim);
                member.pendingClaim = pendingMoney;
            }
            IERC20(s_moneyAddr).transfer(
                msg.sender,
                (s_amount * ActiveMembers * s_periods_claim)
            );
        } else {
            uint256 withdrawPending = member.pendingClaim;

            if (member.pendingClaim > s_amount_late) {
                withdrawPending = s_amount_late;
                member.pendingClaim = member.pendingClaim - s_amount_late;
            }
            IERC20(s_moneyAddr).transfer(msg.sender, (withdrawPending));
        }

        member.claim = true;
        s_members_id[id] = member;
    }

    function updateMember(uint256 id) external {
        MemberData storage member = s_members_id[id];
        if (member.SmartContract != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
    }
    function reStart() external {}

    function addMember(
        uint256 id,
        address addr,
        address smartContract
    ) external onlyRole(MEMBER_ROLE) {
        //need add checks
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
        s_members_turn[id] = s_total_member;
        membersId.push(id);
    }
    function startNatillera() external onlyRole(MEMBER_ROLE) {
        s_time = block.timestamp;
        s_natillera_status = NatilleraStatus.STARTED;
    }

    function period() internal view returns (uint256) {
        return (block.timestamp - s_time) / (30 days);
    }
    //80% thresold
    //80% thresold
    function deleteMember() external {}

    ///////////////////////////////
    ////// INTERNAL FUNCTIONS //////
    ///////////////////////////////

    function is_myTurn(
        uint256 id
    ) internal view Member_Status(id) returns (bool) {
        MemberData memory member = s_members_id[id];
        uint256 turn = s_members_turn[id];
        if (member.claim == true) {
            revert Natillera_Member_already_claim(msg.sender);
        }
        uint256 s_period = period();
        bool ismyturn = false;
        if (s_period < (s_periods_claim * turn)) {
            ismyturn = true;
        }
        return ismyturn;
    }
    //////////////////////////
    ////// VIEW FUNCTIONS ////
    //////////////////////////
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
            uint256[] memory
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
            membersId
        );
    }
    function getdataMember(
        uint256 id
    ) external view returns (MemberData memory, uint256) {
        MemberData memory member = s_members_id[id];
        uint256 turn = s_members_turn[id];
        return (member, turn);
    }
    /**
    
     */
}
