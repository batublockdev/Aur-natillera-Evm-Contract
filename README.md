# AUR — Natillera Contract

> **Status: Work in progress · Not audited · Do not use in production**

A Solidity smart contract that brings the **natillera** — the most common rotating-savings mechanism in Latin America — on-chain. A group of people saves money together in weekly/monthly periods and withdraws the accumulated pot **in turns**, decentralizing the whole group-saving process.

---

## 📖 What is a Natillera?

In a traditional *natillera* (also known as *cundina*, *polla*, *rosca* or *tanda* depending on the country):

1. A fixed number of people commit to saving a fixed amount each period.
2. The total collected each round is paid out to **one member in turn**, rotating until everyone has received their pot.
3. Participants who fall behind become "inactive/late" and lose their claim priority.

`AUR` replicates this on-chain with **transparent rules**, a **turn order**, and **automatic distribution**, removing the need for a trusted human organizer.

---

## ✨ Features

- 🔁 **Rotating payout** — each member collects the pooled funds when their turn arrives.
- 💰 **Fixed periodic deposit** — everyone deposits the same `s_amount` per period (30-day periods).
- 🗓️ **Turn windows** — a member must wait `s_periods_claim` periods before being able to claim.
- ⏰ **Late-payment tracking** — members who fall behind are flagged and their pending funds are protected.
- 🧑‍🤝‍🧑 **Decentralized membership management** — add/remove members and reorder turns while not started.
- 🔄 **Cycle restart** — when the full cycle finishes, `reStart()` redistributes any leftover funds and resets the state.
- 🏦 **ERC-20 based** — deposits/withdrawals use any standard token via SafeERC20.

---

## 🛠️ Stack

| Component | Technology |
|-----------|------------|
| **Language** | Solidity `^0.8.25` |
| **Framework** | Foundry (Forge, Cast, Anvil) |
| **Libraries** | OpenZeppelin — `AccessControl`, `SafeERC20`, `ReentrancyGuard` |
| **Testing** | Foundry test suite + invariant testing (Echidna) |
| **Static analysis** | Slither |

---

## 📁 Project Structure

```
├── src/
│   └── aur.sol                  # Main contract
├── test/
│   ├── aur.t.sol                # Foundry test suite (68 tests)
│   ├── mock/
│   │   └── ERC20Mock.sol        # Test ERC-20 token
│   └── invariants/
│       └── AURInvariants.sol    # Echidna invariant properties
├── script/
│   └── aurDeploy.s.sol          # Deploy script
├── foundry.toml                 # Foundry configuration
├── AUDIT_REPORT.md              # Security audit report
└── .github/
    └── workflows/test.yml       # CI pipeline
```

---

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Git

### Install & build

```bash
git clone <repo-url>
cd aur-natillera-contract

# Install OpenZeppelin dependency
forge install

# Compile
forge build
```

### Run tests

```bash
# Full test suite (68 tests)
forge test

# A single test, verbose
forge test --match-test test_constructor_checks -vvv

# Test with traces
forge test -vvv
```

### Local node & deploy

```bash
# Spin up a local chain
anvil

# Deploy (deployer becomes the first MEMBER)
forge script script/aurDeploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

---

## 🔐 Access Control

`AUR` uses OpenZeppelin `AccessControl` with a single role:

| Role | Description |
|------|-------------|
| `MEMBER_ROLE` | Granted to the deployer (constructor) and to every added member + their associated `SmartContract`. Required for all mutating operations. |

> The role name is computed as `keccak256("MEMBER")` and exposed via the public constant `MEMBER_ROLE`.

---

## 🧩 Contract Lifecycle

The natillera moves through three statuses:

```
SETTING ──(startNatillera)──▶ STARTED ──(reStart, after cycle ends)──▶ SETTING
    ▲                                                                    │
    └────────────────────────────────────────────────────────────────────┘
```

| Status | Meaning |
|--------|---------|
| `SETTING` | Configuration phase. Members, turns and parameters can be changed. Deposits/claims blocked. |
| `STARTED` | Active phase. Deposits and turn claims allowed. Parameters no longer changeable. |
| `PAUSED` | *(defined)* Reserved for an emergency halt. All deposits/claims blocked. |

---

## 🔑 Lifecycle & Management Functions

### Configuration (only when `SETTING`)

| Function | Description |
|----------|-------------|
| `addMember(id, addr, smartContract)` | Adds a member + their smart contract; assigns next turn. Grants `MEMBER_ROLE`. |
| `updateMember(id, newAdr)` | Migrates a member to a new wallet address (only callable by the member's `SmartContract`). |
| `DeleteMember(id)` | Removes a member and reorders the remaining turns. Refunds any pending amount. |
| `ChangeTurn(id, newTurn)` | Moves a member to a new position (1-based) in the turn order. |
| `changeAmount(newAmount)` | Changes the per-period deposit amount. |
| `changePeriods(newPeriods)` | Changes the number of periods before a member can claim. |
| `startNatillera()` | Starts the cycle and records the start timestamp. |

### Active phase (only when `STARTED`)

| Function | Description |
|----------|-------------|
| `deposit_token(id)` | Deposits the period amount for a member `id`. |
| `claim_myTurn(id)` | Claims the collected pot when the caller's turn has arrived. |
| `withdrawAfterContractFinished(id)` | Withdraws redistributed funds after the cycle finished and `reStart()` ran. |
| `reStart()` | Redistributes leftover funds to responsible members and resets all state to a new `SETTING` cycle. |

### Query (view)

| Function | Description |
|----------|-------------|
| `getData()` | Total members, periods-to-claim, amount, start time, token address, status, member IDs, active members. |
| `getdataMember(id)` | Full `MemberData`, turn, and member index. |
| `GetPeriod()` | Current 30-day period number. |
| `Get_member_Status(id)` | How many periods a member is ahead (≥0) or behind (<0). |
| `is_myTurn_ext(id)` | External view: is it this member's turn to claim? |

---

## 🧮 Core Mechanism Explained

- **Periods:** time is divided into 30-day periods: `period() = (block.timestamp - s_time) / 30 days`.
- **Turn ownership:** each member owns a window of `s_periods_claim` consecutive periods. A member becomes claimable once `period() >= s_periods_claim * turn`.
- **Collection tracking:** `s_amount_colleted[period]` / `s_amount_late_colleted[period]` record what was paid on-time and late for each period. `collected_forTurn()` sums the window for a turn.
- **Inactive members:** `member_Status(id) < 0` means the member is behind. Those members can't claim and their slot's funds are preserved for `reStart()` redistribution.
- **Pending claims:** if some members are late (`members_status() != s_total_member`), the shortfall is stored as `member.pendingClaim` and paid out once sufficient late funds accumulate.

---

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

### ⚠️ Known findings (summary)

| ID | Severity | Status |
|----|----------|--------|
| `AUR-01` Over-counting in `collected_forTurn()` → underflow in `reStart()` | High | ✅ **Fixed** & verified (68 tests pass) |
| `AUR-02` `deposit_token()` doesn't validate ID ownership | Medium | ⏳ Open |
| `AUR-03` `changeAmount()`/`changePeriods()` modifiable by any member | Medium | ⏳ Open |
| `AUR-04` Membership collisions / access-control granularity | Medium | ⏳ Open |
| `AUR-05` Uninitialized local variables | Medium | ⏳ Open |
| `AUR-06` `block.timestamp` dependence | Low | ⏳ Open |

> **Note:** the `AUR-01` fix was applied to `collected_forTurn()` **only**. `clean_colleted_money()` (line ~672) still keeps the extra `- 1` in its `endIndex`. This may cause the cleanup window to misalign with the collection window — verify before relying on the full cycle reset.

---

## 🧪 Test Summary

The suite covers: constructor constraints, access-control/role enforcement, member add/update/delete, turn ordering & reordering, deposit & late-payment accounting, per-turn claim windows, `reStart()` redistribution and multi-cycle behavior.

**Current state: `68 passed · 0 failed · 0 skipped`**

---

## 📄 License

`SPDX-License-Identifier: MIT`

---

## 🤝 Contributing / Roadmap

This is an early work-in-progress. Priorities before production:

1. Close the open Medium findings (`AUR-02` → `AUR-05`).
2. Align `clean_colleted_money()` with the `collected_forTurn()` range fix.
3. Remove `console.log` debug statements from the production paths.
4. Full independent audit + invariant hardening.
