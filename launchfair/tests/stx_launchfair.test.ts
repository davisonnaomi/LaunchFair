import { describe, expect, it, beforeEach, vi } from "vitest";

// Mock constants
const mockContractOwner = "SP123OWNER456789";
const initBlockHeight = 100;
const mockTokenContract = "SP123TOKEN456789.my-token";
const mockUsers = [
  "SP123USER1456789",
  "SP123USER2456789",
  "SP123USER3456789"
];

// Mock error codes for assertions
const ERROR_CODES = {
  ERR_OWNER_ONLY: 200,
  ERR_INVALID_PARAMS: 201,
  ERR_PROJECT_EXISTS: 202,
  ERR_PROJECT_NOT_FOUND: 203,
  ERR_NOT_ACTIVE: 204,
  ERR_ZERO_AMOUNT: 205,
  ERR_INSUFFICIENT_BALANCE: 206,
  ERR_ALLOCATION_EXCEEDED: 207,
  ERR_PROJECT_ENDED: 208,
  ERR_PROJECT_NOT_ENDED: 209,
  ERR_ALREADY_CLAIMED: 210,
  ERR_NO_CONTRIBUTION: 211,
  ERR_MAX_CAP_REACHED: 212,
  ERR_LAUNCH_IN_PROGRESS: 213,
  ERR_MAX_PROJECTS_REACHED: 214,
  ERR_NOT_WHITELISTED: 215
};

// Distribution types
const DIST_TYPES = {
  FIXED_PRICE: 0,
  DUTCH_AUCTION: 1,
  FAIR_LAUNCH: 2
};

// Project statuses
const PROJECT_STATUS = {
  PENDING: 0,
  ACTIVE: 1,
  ENDED: 2,
  CANCELED: 3
};

// Mock implementation of the Launchpad contract
class MockLaunchpad {
  constructor(owner) {
    this.owner = owner;
    this.projectCount = 0;
    this.projects = new Map();
    this.contributions = new Map();
    this.projectContributions = new Map();
    this.whitelist = new Map();
    this.projectTokens = new Map();
    this.paymentTokenBalances = new Map();
  }

  // Helper to get key string for maps
  getProjectKey(projectId) {
    return `project-${projectId}`;
  }
  
  getContributionKey(projectId, user) {
    return `contribution-${projectId}-${user}`;
  }
  
  getWhitelistKey(projectId, user) {
    return `whitelist-${projectId}-${user}`;
  }
  
  getTokenKey(tokenContract) {
    return `token-${tokenContract}`;
  }

  // Implementation of contract functions
  createProject(sender, {
    name,
    tokenContract,
    tokenSymbol,
    duration,
    totalTokens,
    distributionType,
    priceParams,
    raiseParams,
    individualLimits,
    useWhitelist
  }) {
    // Check owner
    if (sender !== this.owner) {
      return { error: ERROR_CODES.ERR_OWNER_ONLY };
    }

    // Validate parameters
    if (duration <= 5000 || totalTokens <= 0) {
      return { error: ERROR_CODES.ERR_INVALID_PARAMS };
    }

    // Check if token contract is already used
    if (this.projectTokens.has(this.getTokenKey(tokenContract))) {
      return { error: ERROR_CODES.ERR_PROJECT_EXISTS };
    }

    const projectId = this.projectCount;
    const currentBlock = vi.mocked(global["burn-block-height"])();

    // Create project
    this.projects.set(this.getProjectKey(projectId), {
      name,
      tokenContract,
      creator: sender,
      tokenSymbol,
      startBlock: currentBlock,
      endBlock: currentBlock + duration,
      totalTokens,
      tokensSold: 0,
      status: PROJECT_STATUS.ACTIVE,
      distributionType,
      pricePerToken: priceParams.pricePerToken,
      minPrice: priceParams.minPrice,
      maxPrice: priceParams.maxPrice,
      minRaise: raiseParams.minRaise,
      maxRaise: raiseParams.maxRaise,
      individualMin: individualLimits.min,
      individualMax: individualLimits.max,
      useWhitelist
    });

    // Initialize project contributions
    this.projectContributions.set(this.getProjectKey(projectId), {
      totalRaised: 0
    });

    // Map token contract to project id
    this.projectTokens.set(this.getTokenKey(tokenContract), {
      projectId
    });

    // Increment project count
    this.projectCount++;

    return { value: projectId };
  }

  addToWhitelist(sender, projectId, users) {
    // Check owner
    if (sender !== this.owner) {
      return { error: ERROR_CODES.ERR_OWNER_ONLY };
    }

    // Check project exists
    if (!this.projects.has(this.getProjectKey(projectId))) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_FOUND };
    }

    const project = this.projects.get(this.getProjectKey(projectId));

    // Check project is in correct state
    if (project.status !== PROJECT_STATUS.PENDING) {
      return { error: ERROR_CODES.ERR_LAUNCH_IN_PROGRESS };
    }

    // Add users to whitelist
    for (const user of users) {
      this.whitelist.set(this.getWhitelistKey(projectId, user), {
        whitelisted: true
      });
    }

    return { value: true };
  }

  contribute(sender, projectId, amount) {
    // Validate amount
    if (amount <= 0) {
      return { error: ERROR_CODES.ERR_ZERO_AMOUNT };
    }

    // Check project exists
    if (!this.projects.has(this.getProjectKey(projectId))) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_FOUND };
    }

    const project = this.projects.get(this.getProjectKey(projectId));
    const currentBlock = vi.mocked(global["burn-block-height"])();

    // Check project is active
    if (project.status !== PROJECT_STATUS.ACTIVE) {
      return { error: ERROR_CODES.ERR_NOT_ACTIVE };
    }

    // Check project has not ended
    if (currentBlock > project.endBlock) {
      return { error: ERROR_CODES.ERR_PROJECT_ENDED };
    }

    // Check whitelist if required
    if (project.useWhitelist) {
      const whitelistKey = this.getWhitelistKey(projectId, sender);
      if (!this.whitelist.has(whitelistKey) || !this.whitelist.get(whitelistKey).whitelisted) {
        return { error: ERROR_CODES.ERR_NOT_WHITELISTED };
      }
    }

    // Get or initialize user contribution
    const contributionKey = this.getContributionKey(projectId, sender);
    const userContribution = this.contributions.has(contributionKey) 
      ? this.contributions.get(contributionKey) 
      : { amount: 0, tokensClaimed: false };
    
    const newAmount = userContribution.amount + amount;

    // Check individual min contribution
    if (project.individualMin > 0 && newAmount < project.individualMin) {
      return { error: ERROR_CODES.ERR_INVALID_PARAMS };
    }

    // Check individual max contribution
    if (project.individualMax > 0 && newAmount > project.individualMax) {
      return { error: ERROR_CODES.ERR_ALLOCATION_EXCEEDED };
    }

    // Get project contributions
    const projectKey = this.getProjectKey(projectId);
    const projectContrib = this.projectContributions.get(projectKey);
    const newTotal = projectContrib.totalRaised + amount;

    // Check max cap
    if (newTotal > project.maxRaise) {
      return { error: ERROR_CODES.ERR_MAX_CAP_REACHED };
    }

    // Update user contribution
    this.contributions.set(contributionKey, {
      amount: newAmount,
      tokensClaimed: false
    });

    // Update project contributions
    this.projectContributions.set(projectKey, {
      totalRaised: newTotal
    });

    return { value: newAmount };
  }

  finalizeProject(sender, projectId) {
    // Check project exists
    if (!this.projects.has(this.getProjectKey(projectId))) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_FOUND };
    }

    const project = this.projects.get(this.getProjectKey(projectId));
    const currentBlock = vi.mocked(global["burn-block-height"])();

    // Check project is active
    if (project.status !== PROJECT_STATUS.ACTIVE) {
      return { error: ERROR_CODES.ERR_NOT_ACTIVE };
    }

    // Check project has ended
    if (currentBlock <= project.endBlock) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_ENDED };
    }

    // Get project contributions
    const projectKey = this.getProjectKey(projectId);
    const projectContrib = this.projectContributions.get(projectKey);

    // Update project status based on whether min raise was met
    if (projectContrib.totalRaised >= project.minRaise) {
      project.status = PROJECT_STATUS.ENDED;
    } else {
      project.status = PROJECT_STATUS.CANCELED;
    }

    this.projects.set(projectKey, project);
    return { value: true };
  }

  claimTokens(sender, projectId) {
    // Check project exists
    if (!this.projects.has(this.getProjectKey(projectId))) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_FOUND };
    }

    const project = this.projects.get(this.getProjectKey(projectId));

    // Check project has ended successfully
    if (project.status !== PROJECT_STATUS.ENDED) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_ENDED };
    }

    // Get user contribution
    const contributionKey = this.getContributionKey(projectId, sender);
    if (!this.contributions.has(contributionKey)) {
      return { error: ERROR_CODES.ERR_NO_CONTRIBUTION };
    }

    const userContrib = this.contributions.get(contributionKey);

    // Check contribution exists and has not been claimed
    if (userContrib.amount <= 0) {
      return { error: ERROR_CODES.ERR_NO_CONTRIBUTION };
    }

    if (userContrib.tokensClaimed) {
      return { error: ERROR_CODES.ERR_ALREADY_CLAIMED };
    }

    // Calculate token allocation
    const tokenAmount = this.calculateAllocation(projectId, sender);

    // Mark as claimed
    userContrib.tokensClaimed = true;
    this.contributions.set(contributionKey, userContrib);

    // Update tokens sold
    project.tokensSold += tokenAmount;
    this.projects.set(this.getProjectKey(projectId), project);

    return { value: tokenAmount };
  }

  // Helper function to calculate allocation
  calculateAllocation(projectId, user) {
    const project = this.projects.get(this.getProjectKey(projectId));
    const contributionKey = this.getContributionKey(projectId, user);
    const userContrib = this.contributions.get(contributionKey);
    const projectContrib = this.projectContributions.get(this.getProjectKey(projectId));
    
    const contributionAmount = userContrib.amount;
    const precision = 1000000; // From smart contract
    
    // Different distribution mechanisms
    if (project.distributionType === DIST_TYPES.FIXED_PRICE) {
      // Fixed price: tokens = contribution / price-per-token
      return Math.floor((contributionAmount * precision) / project.pricePerToken);
    } else if (project.distributionType === DIST_TYPES.DUTCH_AUCTION) {
      // Dutch auction: calculate final price based on demand
      const finalPrice = this.calculateDutchAuctionPrice(projectId);
      return Math.floor((contributionAmount * precision) / finalPrice);
    } else {
      // Fair launch: proportional to contribution
      const totalRaised = projectContrib.totalRaised;
      const totalTokens = project.totalTokens;
      
      if (totalRaised > 0) {
        return Math.floor((contributionAmount * totalTokens) / totalRaised);
      } else {
        return 0;
      }
    }
  }
  
  // Calculate dutch auction price
  calculateDutchAuctionPrice(projectId) {
    const project = this.projects.get(this.getProjectKey(projectId));
    const projectContrib = this.projectContributions.get(this.getProjectKey(projectId));
    const totalRaised = projectContrib.totalRaised;
    const minPrice = project.minPrice;
    const maxPrice = project.maxPrice;
    const totalTokens = project.totalTokens;
    const precision = 1000000;
    
    if (totalRaised >= project.maxRaise) {
      // If max raise is reached, calculate price based on demand
      const impliedPrice = Math.floor((totalRaised * precision) / totalTokens);
      
      if (impliedPrice > maxPrice) {
        return maxPrice;
      } else if (impliedPrice < minPrice) {
        return minPrice;
      } else {
        return impliedPrice;
      }
    } else {
      // Otherwise use minimum price
      return minPrice;
    }
  }
  
  // Get project details
  getProjectDetails(projectId) {
    const projectKey = this.getProjectKey(projectId);
    if (!this.projects.has(projectKey) || !this.projectContributions.has(projectKey)) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_FOUND };
    }
    
    const project = this.projects.get(projectKey);
    const projectContrib = this.projectContributions.get(projectKey);
    
    return { 
      value: {
        ...project,
        totalRaised: projectContrib.totalRaised
      }
    };
  }
  
  // Get user allocation
  getUserAllocation(projectId, user) {
    const projectKey = this.getProjectKey(projectId);
    const contributionKey = this.getContributionKey(projectId, user);
    
    if (!this.projects.has(projectKey) || !this.contributions.has(contributionKey)) {
      return { error: ERROR_CODES.ERR_PROJECT_NOT_FOUND };
    }
    
    const project = this.projects.get(projectKey);
    const userContrib = this.contributions.get(contributionKey);
    
    return {
      value: {
        contribution: userContrib.amount,
        tokensClaimed: userContrib.tokensClaimed,
        tokenAllocation: this.calculateAllocation(projectId, user)
      }
    };
  }
}

describe("Token Launchpad", () => {
  let launchpad;
  let currentBlockHeight;

  beforeEach(() => {
    currentBlockHeight = initBlockHeight;
    // Mock the chain's burn-block-height function
    vi.stubGlobal("burn-block-height", () => currentBlockHeight);
    launchpad = new MockLaunchpad(mockContractOwner);
  });

})

