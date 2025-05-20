Token Launchpad - Fair Token Distribution Platform
Author: Claude
Date: 2025-05-20
Language: Clarity (Stacks Smart Contract)

📘 Overview
Token Launchpad is a smart contract platform designed to launch new tokens with fair, transparent, and decentralized distribution mechanisms. It supports various fundraising formats, including:

Fixed Price Sales

Dutch Auctions

Fair Launches (Proportional Allocation)

The platform allows creators to configure detailed parameters, use optional whitelisting, and ensure fair participation with defined contribution caps and automated allocation logic.

✨ Features
✅ Create launch projects with customizable tokenomics

✅ Three distribution types: Fixed, Dutch Auction, Fair Launch

✅ Minimum/maximum caps (global and per-user)

✅ Whitelist control per project

✅ Automatic finalization based on block height

✅ Refunds for failed launches

✅ Token claiming for successful participants

✅ Secure with ownership controls and error handling

🛠 Project Structure
Smart Contract Constants
contract-owner: Set on deployment, owner-only functions

Launch configuration limits:

min-launch-duration, max-projects, precision

Distribution types and statuses are encoded with uint constants.

Data Maps
projects: Stores all token launch configurations

contributions: Tracks user contributions and claim status

project-contributions: Aggregates total raised funds

whitelist: Optional participation restrictions

project-tokens: Prevents reuse of token contracts

🚀 Usage
📦 Launch a Project
Use create-project to configure and deploy a new launch. You must provide:

Project metadata (name, symbol, token contract)

Token supply and distribution type

Price details (fixed or auction params)

Raise targets and individual limits

Optional whitelist toggle

👥 Manage Whitelist
Before launch starts, whitelist participants via add-to-whitelist. Only whitelisted users can participate in restricted projects.

💸 Contribute
Users participate using the contribute function by sending payment-token. The contract enforces all caps and checks eligibility.

✅ Finalize Launch
After the end block, the owner finalizes the launch with finalize-project to determine success/failure based on raised funds.

🎁 Claim Tokens
Participants in successful launches use claim-tokens to receive allocations calculated per the selected distribution type.

💰 Get Refund
In canceled or failed launches, users reclaim their contributions via get-refund.

📖 Read-Only Functions
get-project-details: Fetch metadata and status of a project

get-user-allocation: Retrieve contribution and token allocation for a user

🧠 Distribution Types Explained
Type	Description
dist-fixed-price	Price per token is constant
dist-dutch-auction	Price decreases over time, final price based on demand
dist-fair-launch	Tokens allocated proportionally to contributions

🔐 Security & Validations
The contract includes:

Strict access control for project creation and whitelist management

Comprehensive input validation

Re-entrancy-safe contribution and claiming logic

Overflow-safe math using uint and Clarity assertions

🪙 Payment Token
All contributions use a fungible token (payment-token) representing a stablecoin or utility token. In production, replace this with a verified stable token.