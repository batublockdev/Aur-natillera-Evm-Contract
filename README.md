# AUR — Natillera Contract

A Solidity smart contract that brings on-chain the most common saving mechanism in
Latin America: the **natillera**. A group of people saves money together and withdraws
it in turns, decentralizing the group saving process.

> ⚠️ **Status:** Work in progress. Not audited. **Do not use in production.**

## 📋 Description

The `aur` contract allows a group of people to:

- **Save** by depositing a fixed amount per period (monthly).
- **Withdraw** the accumulated money in turns, according to the established order.
- **Manage** members, turns, and natillera parameters in a decentralized way.

Each member deposits `s_amount` per period. When their turn arrives (after
`s_periods_claim` periods), they can claim the collected money. If there are inactive
members (late on payments), the pending money accumulates as `pendingClaim` to be
claimed later.

## 🛠️ Stack

- **Language:** Solidity `^0.8.25`
- **Framework:** [Foundry](https://book.getfoundry.sh/) (Forge, Cast, Anvil)
- **Libraries:** OpenZeppelin (AccessControl, SafeERC20, ReentrancyGuard)
- **Security:** Slither, Echidna (invariant fuzzing)

## 📁 Project Structure

```
├── src/
│   └── aur.sol              # Main contract
├── test/
│   ├── aur.t.sol            # Test suite (Foundry)
│   ├── mock/
│   │   └── ERC20Mock.sol    # Test ERC20 token
│   └── invariants/
│       └── AURInvariants.sol # Echidna invariants
├── script/
│   └── aurDeploy.s.sol      # Deploy script
├── foundry.toml             # Foundry configuration
└── AUDIT_REPORT.md          # Security audit report
```

## 🚀 Installation

```bash
# Clone the repo
git clone <repo-url>
cd aur-natillera-contract

# Install dependencies (OpenZeppelin)
forge install

# Build
forge build
```

## 🧪 Tests

```bash
# Run all tests
forge test

# Run a specific test
forge test --match-test test_constructor_checks -vvv
```

## 🔍 Security Analysis

### Slither (static analysis)

```bash
slither .
```

### Echidna (invariant fuzzing)

```bash
echidna test/invariants/AURInvariants.sol \
  --contract AURInvariants \
  --test-mode property \
  --test-limit 20000
```

> See [`AUDIT_REPORT.md`](./AUDIT_REPORT.md) for the full audit report.

## 📜 Main Functions

### Member Management

| Function | Description |
|----------|-------------|
| `addMember(id, addr, smartContract)` | Adds a member to the natillera |
| `updateMember(id, newAdr)` | Updates a member's address |
| `deleteMember(id)` | Deletes a member (⚠️ placeholder) |
| `DeleteMember(id)` | Removes a member from the turn order |

### Deposits & Withdrawals

| Function | Description |
|----------|-------------|
| `deposit_token(id)` | Deposits the period amount |
| `claim_myTurn(id)` | Claims the money when it is the member's turn |

### Configuration

| Function | Description |
|----------|-------------|
| `changeAmount(newAmount)` | Changes the per-period amount |
| `changePeriods(newPeriods)` | Changes the periods to claim |
| `startNatillera()` | Starts the natillera |
| `ChangeTurn(id, newTurn)` | Moves a member in the turn order |

### Queries (view)

| Function | Description |
|----------|-------------|
| `getData()` | General natillera data |
| `getdataMember(id)` | Data of a specific member |
| `GetPeriod()` | Current period |
| `Get_member_Status(id)` | Member payment status |
| `is_myTurn_ext(id)` | Checks if it is a member's turn |

## 🧠 Turn Model

- Each member has a **turn** (1, 2, 3...).
- A member can claim when the current period `>= s_periods_claim * turn`.
- If there are inactive members, the money that could not be collected is stored as
  `pendingClaim` and claimed on the next turn.

## ⚠️ Known Limitations

- `deleteMember` is a placeholder (does not revoke the role or clean up mappings).
- `updateMember` has no `onlyRole` (membership theft risk if `SmartContract` is an
  EOA wallet).
- Relies on `block.timestamp` to calculate periods.
- `s_amount_late` is dead code (always returns 0).

## 📄 License

MIT

---

*Developed by [batublockdev](https://github.com/batublockdev).*
