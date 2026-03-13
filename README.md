# Token Vesting

ERC-20 token vesting contract with **cliff + linear release**. Written in Solidity with comprehensive Foundry tests.

## What is Token Vesting?

Token vesting locks tokens over time, releasing them gradually. This is standard practice for team allocations, investor tokens, and contributor rewards — preventing immediate dumping.

## Vesting Model

```
Tokens
 ^
 |                              ████████████ (fully vested)
 |                         █████
 |                    █████
 |               █████
 |          █████
 |         .|
 |         .|  (cliff — no tokens before here)
 |.........|
 +----------+--------+--------+----> Time
  start    cliff    halfway   end
```

**Cliff:** No tokens can be released before the cliff date.  
**Linear:** After the cliff, tokens vest linearly from the start time.

### Example

- 1,000,000 tokens, 4-year vest, 1-year cliff
- At 1 year (cliff): ~25% is releasable (1,000,000 × 365/1460)
- At 2 years: ~50% total vested, minus already released
- At 4 years: 100% released

## Contract Functions

| Function | Access | Description |
|---|---|---|
| `createVestingSchedule(...)` | Owner | Create a new schedule |
| `release(scheduleId)` | Beneficiary/Owner | Release vested tokens |
| `revoke(scheduleId)` | Owner | Cancel revocable schedule |
| `computeReleasableAmount(id)` | View | How many tokens can be released |
| `getVestingSchedule(id)` | View | Full schedule details |
| `computeVestingScheduleId(addr, idx)` | Pure | Derive schedule ID |

## Setup

```bash
git clone https://github.com/7abar/token-vesting
cd token-vesting
forge install foundry-rs/forge-std
```

## Run Tests

```bash
forge test
forge test -vvv
forge coverage
```

## Deploy

```bash
export VESTING_TOKEN=0xYourTokenAddress
export PRIVATE_KEY=0xYourPrivateKey

forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY
```

## Create a Vesting Schedule (Cast)

```bash
# Approve tokens first (send tokens to the vesting contract)
cast send $TOKEN_ADDRESS "transfer(address,uint256)" $VESTING_CONTRACT 1000000000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url base_sepolia

# Create schedule: alice, start now, 1yr cliff, 4yr duration, 1M tokens, revocable
cast send $VESTING_CONTRACT \
  "createVestingSchedule(address,uint256,uint256,uint256,uint256,bool)" \
  0xAliceAddress $(date +%s) $((365*24*3600)) $((4*365*24*3600)) 1000000000000000000000000 true \
  --private-key $PRIVATE_KEY --rpc-url base_sepolia

# Release vested tokens (call as alice or owner)
cast send $VESTING_CONTRACT "release(bytes32)" $SCHEDULE_ID \
  --private-key $ALICE_KEY --rpc-url base_sepolia
```

## License

MIT
