// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

//imports
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {
    SignatureChecker
} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    MessageHashUtils
} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/*
    @title aur
    @author batublockdev
    @notice This contract is a natillera contract which brings onchain the most commun saving mechanism in latin america.
     It allows a group of people to save money together and withdraw it in turns. The contract is designed to be used by 
     a group of people setting up the rules of the saving mechanism and decentralizing the process of saving money as a group. 
    @dev This contract is a work in progress and is not yet complete. It is not yet audited and should not be used in production.
*/

contract aur is EIP712, Ownable {
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

    uint256 private s_nonce;
    uint256 private s_total_member;
    uint256 private s_amount_late;
    uint16 private s_periods_claim;
    uint256 private s_amount;
    uint256 private s_time;
    address private immutable s_moneyAddr;

    NatilleraStatus private s_natillera_status;

    mapping(uint256 => MemberData) private s_members_id;
    mapping(address addr => uint256 id) private s_members_addr;
    mapping(uint64 id => uint64 turn) private s_members_turn;
    uint64[] private membersId;

    using ECDSA for bytes32;

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
        uint256 turn;
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
        int168 periodMember = member_Status(id);
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
    constructor(
        address _moneyAddr,
        uint256 _amount,
        uint16 _periods_claim
    ) EIP712("Natillera", "1.0") Ownable(msg.sender) {
        s_moneyAddr = _moneyAddr;
        s_amount = _amount;
        s_natillera_status = NatilleraStatus.SETTING;
        s_time = block.timestamp;
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
        if (amount == 0 || amount < s_amount) revert Natillera_Wrong_Amount();
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
        int168 periodMember = member_Status(id);
        if (periodMember < 0) {
            s_amount_late += amount;
        }

        member.latestPeriod++;
        s_members_id[id] = member;
    }

    //we check member status
    //member no active can't withdraw
    //so if there are just
    //if we got
    function members_status() internal view returns (uint64) {
        uint64 numberActiveMember;
        for (uint256 index = 0; membersId.length; index++) {
            int168 periodMember = member_Status(membersId[index]);
            if (periodMember >= 0) {
                numberActiveMember++;
            }
        }
        return numberActiveMember;
    }
    function member_Status(uint256 id) internal returns (int168) {
        int168 periods;
        uint256 memory s_period = period();
        MemberData memory member = s_members_id[id];
        periods = s_period - member.LatestPeriod;
        return periods;
    }
    function is_myTurn_ext(uint256 id) external view returns (bool) {
        bool memory turn = is_myTurn(id);
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
        for (uint256 index = item; membersId.length - 1; index++) {
            membersId[index] = membersId[index + 1];
            s_members_turn[membersId[index + 1]] = index + 1;
        }
        membersId.pop();
    }
    function changeAmount(uint256 newAmount) external {
        uint256 id = s_members_addr[msg.sender];
        if (id == 0) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (newAmount == 0) revert Wallet_CantBeZero();
        s_amount = newAmount;
    }
    function changePeriods(uint256 newPeriods) external {
        uint256 id = s_members_addr[msg.sender];
        if (id == 0) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        if (newPeriods == 0) revert Wallet_CantBeZero();
        s_periods_claim = newPeriods;
    }
    function changeTurns(uint256 id, uint256 newTurn) internal {
        uint64 item = s_members_turn[id];
        item--;
        setTurnOrder(item);
    }
    function DeleteMember(uint256 id) internal {
        uint64 item = s_members_turn[id];
        item--;
        setTurnOrder(item);
    }
    function claim_myTurn(uint256 id) external Member_Status {
        MemberData storage member = s_members_id[id];
        if (member.addr != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        bool memory m_ismyturn = is_myTurn(id);
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
            IERC20(s_moneyAddr).safeTransfer(
                msg.sender,
                (s_amount * ActiveMembers * s_periods_claim)
            );
        } else {
            uint256 withdrawPending = member.pendingClaim;

            if (member.pendingClaim > s_amount_late) {
                withdrawPending = s_amount_late;
                member.pendingClaim = member.pendingClaim - s_amount_late;
            }
            IERC20(s_moneyAddr).safeTransfer(msg.sender, (withdrawPending));
        }

        member.claim = true;
        s_members_id[id] = member;
    }

    function updateMember(uint256 id) external {
        MemberData storage member = s_members_id[id];
        if (member.smartContract != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
    }
    function reStart() external {}
    function getData() external {}

    function addMember(
        uint256 id,
        address addr,
        address smartContract,
        uint256 turn
    ) external onlyOwner {
        s_members_id[id] = MemberData({
            id: id,
            addr: addr,
            smartContract: smartContract,
            latestPeriod: 0
        });
        s_members_addr[addr] = id;
        s_total_member++;
        s_members_turn[id] = s_total_member;
        membersId.push(id);
    }
    function startNatillera() external onlyOwner {
        s_natillera_status = NatilleraStatus.STARTED;
    }
    //Requiered verification
    //60% thresold
    //Memory copia temporal
    //storage address real
    function Withdraw(
        uint256 id,
        uint256 amount,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external Natillera_Status Member_Status(id) {
        MemberData memory member = s_members_id[id];
        if (member.addr != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        bytes32 digest = _getMessageHash(member.addr, amount);
        if (!_isValidSignature(digest, _v, _r, _s)) {
            revert Wallet_SignatureInvalid();
        }
        s_nonce++;
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
    /**
     * @dev This function returns the message hash for the claim_Check function.
     * @param account The address to transfer the funds to.
     * @param amount The amount to transfer.
     * @param token The address of the token to transfer.
     * @return The message hash.
     */

    function _getMessageHash(
        address account,
        uint256 amount,
        address token
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MESSAGE_TYPEHASH,
                        CheckClaim({
                            spender: account,
                            value: amount,
                            nonce: s_nonce,
                            deadline: block.timestamp + 30 days
                        })
                    )
                )
            );
    }

    /**
     * @dev This function checks if the signature is valid.
     * @param digest The message hash.
     * @param _v The recovery byte of the signature.
     * @param _r The r value of the signature.
     * @param _s The s value of the signature.
     * @return True if the signature is valid, false otherwise.
     */
    function _isValidSignature(
        bytes32 digest,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal view returns (bool) {
        // could also use SignatureChecker.isValidSignatureNow(signer, digest, signature)
        (
            address actualSigner /*ECDSA.RecoverError recoverError*/ /*bytes32 signatureLength*/,
            ,

        ) = ECDSA.tryRecover(digest, _v, _r, _s);
        return (actualSigner == i_owner);
    }
    function is_myTurn(uint256 id) internal Member_Status(id) returns (bool) {
        MemberData memory member = s_members_id[id];
        uint64 turn = s_members_turn[id];
        if (member.claim == true) {
            revert Natillera_Member_already_claim(msg.sender);
        }
        uint256 memory s_period = period();
        bool ismyturn = false;
        if (s_period < (s_periods_claim * turn)) {
            ismyturn = true;
        }
        return ismyturn;
    }
    //////////////////////////
    ////// VIEW FUNCTIONS ////
    //////////////////////////
    /**
     * @dev This function returns the message hash for the claim_Check function.
     * @param account The address to transfer the funds to.
     * @param amount The amount to transfer.
     * @param token The address of the token to transfer.
     * @return The message hash.
     * @dev The function is view, so it does not modify the state of the contract.
     */
    function getMessageHash(
        address account,
        uint256 amount,
        address token
    ) external view returns (bytes32) {
        return _getMessageHash(account, amount, token);
    }
}
