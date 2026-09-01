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
    @title Natillera
    @author batublockdev
    @notice This contract is a natillera contract which brings onchain the most commun saving mechanism in latin america.
     It allows a group of people to save money together and withdraw it in turns. The contract is designed to be used by 
     a group of people setting up the rules of the saving mechanism and decentralizing the process of saving money as a group. 
    @dev This contract is a work in progress and is not yet complete. It is not yet audited and should not be used in production.
*/

contract aurnatillera is EIP712, Ownable {
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

    /**
     * @dev This modifier checks if the amount is not zero.
     * If it is zero, it reverts with a custom error.
     * @param amount The amount to check.
     */
    modifier cantbezero(uint256 amount) {
        if (amount == 0) revert Wallet_CantBeZero();
        _;
    }

    uint256 private s_nonce;
    uint16 private s_period_claim;
    uint256 private s_amount;
    uint256 private s_time;
    address private immutable s_moneyAddr;

    NatilleraStatus private s_natillera_status;

    mapping(uint256 => MemberData) private s_members_id;
    mapping(address addr => uint256 id) private s_members_addr;

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
        uint256 memory s_period = period();
        MemberData memory member = s_members_id[id];
        if (s_period > member.LatestPeriod) {
            //Member is late
            //if member hasn't paid, he can't whitdraw
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
    constructor(
        address _moneyAddr,
        uint256 _amount,
        uint16 _period_claim
    ) EIP712("Natillera", "1.0") Ownable(msg.sender) {
        s_moneyAddr = _moneyAddr;
        s_natillera_status = NatilleraStatus.SETTING;
        s_time = block.timestamp;
        s_period_claim = _period_claim;
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
    ) external cantbezero(amount) Natillera_Status {
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
        MemberData storage member = s_members_id[id];
        member.latestPeriod++;
        s_members_id[id] = member;
    }

    //We need a rebase token to check the turns
    //We need to verify members
    //Each member will have a turn number 1, 2 , 3 .. and can be apply each 3 periods
    //so if memeber x has turn 2 we check if we are in period 6 or if already pass that on so he can access to the money
    //we need a also a track to avoid doble claiming
    // we need a funtion to restar values like period and claim+
    //We want this to happen in a especific order because of the birthdays
    //otherwise we need to add a ramdoness feature can be from chainlink
    function myTurn(uint256 id) external {
        MemberData memory member = s_members_id[id];
        if (member.addr != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        //if is_myTurn()
        //transfer
    }
    function is_myTurn(
        uint256 id
    ) external view Member_Status(id) returns (bool) {
        MemberData memory member = s_members_id[id];
        if (member.claim == true) {
            revert Natillera_Member_already_claim(msg.sender);
        }
        uint256 memory s_period = period();
        bool ismyturn = false;
        if (s_period < (s_period_claim * member.turn)) {
            ismyturn = true;
        }
        return ismyturn;
    }
    function updateMember(uint256 id) external {
        MemberData storage member = s_members_id[id];
        if (member.smartContract != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
    }
    function reStart() external onlyOwner {}

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
            turn: turn,
            latestPeriod: 0
        });
        s_members_addr[addr] = id;
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
        address token,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external Natillera_Status Member_Status(id) {
        MemberData memory member = s_members_id[id];
        if (member.addr != msg.sender) {
            revert Wallet__SpenderNotValid(msg.sender);
        }
        bytes32 digest = _getMessageHash(member.addr, amount, token);
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
