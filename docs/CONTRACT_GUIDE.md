# Using the contracts

## Tokens and NFTs

Use StandardERC20 when the issuer needs to create more supply later. Holders can burn their own tokens; `burnFrom` requires allowance. An ERC-2612 permit authorizes an allowance using a signed message with a deadline and nonce. It is not a gasless token transfer by itself, and wallets still need to show the spender and amount clearly. Each clone has its own signing domain.

Use the tax token only when every integration understands transfer taxes. A 500 basis-point rate is 5%, rounded up to the next smallest unit. A one-unit transfer can therefore deliver zero units to the recipient. The owner starts exempt and can change exemptions, the beneficiary, and the tax rate. No exchange/router compatibility is promised.

NFT IDs begin at zero. Metadata is `baseURI + tokenId`. Set the final URI before locking it: the lock is irreversible and does not freeze the hosted files behind an HTTP URL. There is no supply cap or public mint sale in this template.

## Vesting

The creator is the initial beneficiary. A start of `t` and duration of 100 seconds releases half the cumulative funded amount at `t + 50`. Duration zero releases everything at `t`. Later deposits follow the original schedule, so they can be partly or fully releasable immediately.

Anyone can trigger release, but assets go to the current beneficiary. Ownership can be transferred, including the right to unvested assets. Renouncing ownership is disabled. On chains representing the native asset as an ERC20 as well, do not fund both release paths for the same underlying balance without a chain-specific review.

## Airdrops

Registration flow: create the clone, transfer tokens into it, set the amount per address, then open registration. Registration reserves funds, and the owner cannot withdraw those reservations. Changing the base amount affects only later registrants. The owner can batch-register custom allocations, provided they are funded. Claiming can be enabled independently. A failed token transfer rolls back the claim.

Open registration does not establish identity. One person can register many wallets and consume the budget. Keep public registration closed and use owner-approved batches or a Merkle list when eligibility matters. Use conventional, non-rebasing, non-taxed tokens.

Merkle flow: build a list with OpenZeppelin `StandardMerkleTree` using `["address", "uint256"]`; amounts must be decimal strings in smallest units. The contract uses the corresponding double-hashed ABI leaf. Fund the contract and let each recipient submit their proof. One address can claim once per deployed contract; changing the root does not reset claims. The owner can change eligibility or withdraw the funds, so recipients trust that owner. Deploy a new contract for a new round. The example script contains sample addresses, not a production distribution.

## Staking rewards

The farm distributes funded assets. It does not generate external yield or mint rewards. Pool weights divide emissions: weights 100 and 300 receive 25% and 75% respectively while both have stake. Empty pools do not redistribute their share. Adding or changing weights checkpoints existing pools first, regardless of the retained legacy boolean argument.

The pool tracks credited principal independently from its token balance. Donations cannot dilute the reward calculation. A staking asset cannot also be the reward asset, preventing rewards from consuming staked principal. Use conventional fixed-balance tokens. A token that later rebases, taxes transfers, blacklists holders, or changes behavior can still break withdrawal assumptions.

Normal withdrawal pays available rewards and retains any unpaid balance. `withdraw(pid, 0)` can claim outstanding rewards even after a full principal withdrawal. Emergency withdrawal returns the recorded principal and forfeits all accrued and unpaid rewards. Deposit fees can be as high as 100%; show the exact net stake before confirmation. Farm owners can change future weights, emissions, and deposit fees. No future return is guaranteed.

## Factories and fees

Pay the displayed creation fee plus any native vesting principal. Excess native currency is refunded. A wallet unable to receive refunds should send the exact required amount. A referral may receive a fee share, except for a direct self-referral. Sybil-based self-referrals cannot be prevented by comparing addresses.

Referral calls receive at most 100,000 gas. If the receiver rejects payment, the fee stays in the factory; there is no deferred referral balance. The fee collector can collect accumulated fees. Recovery of accidentally sent ERC20s sends them to the configured collector, not the factory owner. Protocol administrators must treat implementation selection and fee configuration as deployment controls.

## Interface design

Every template should show a short purpose statement, parameter units with a human-readable conversion, owner powers, funding requirements, fees, and irreversible actions. Preview the creator, chain, implementation code hash, recipient, and resulting supply or net deposit before signing. Start users on a testnet and provide verified source links after deployment. Use separate beginner and advanced templates; avoid hiding tax or administrative powers behind an optional checkbox.
