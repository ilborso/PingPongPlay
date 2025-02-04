// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title PingPongPlay
 * @dev ERC20 Token con funzionalità di staking, vesting e gestione della liquidità.
 */
contract PingPongPlay is ERC20, Ownable(address(this)), ReentrancyGuard, ERC20Burnable {
    using SafeMath for uint256;

    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;
    
    // Allocazione dei token
    uint256 public constant PUBLIC_SALE = TOTAL_SUPPLY * 40 / 100;
    uint256 public constant TEAM_FOUNDERS = TOTAL_SUPPLY * 20 / 100;
    uint256 public constant MARKETING_PARTNERSHIP = TOTAL_SUPPLY * 15 / 100;
    uint256 public constant PROJECT_DEVELOPMENT = TOTAL_SUPPLY * 10 / 100;
    uint256 public constant RESERVE = TOTAL_SUPPLY * 10 / 100;
    uint256 public constant COMMUNITY_REWARDS = TOTAL_SUPPLY * 5 / 100;

    // Variabili per il vesting del team e fondatori
    uint256 public vestingStart;
    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public teamReleased;

    // Variabili per lo staking
    struct Stake {
        uint256 amount;       // Importo dello stake
        uint256 timestamp;    // Timestamp dell'ultimo aggiornamento dello stake
        uint256 lastClaimed;  // Ultima volta che l'interesse è stato rilasciato
    }

    mapping(address => Stake) public stakes;
    address[] public stakeAddresses; // mantiene la lista di tutti gliindirizzi cheh hanno effettuato stake
    uint256 public rewardRate; // Tasso di ricompensa annuale in percentuale

    /**
     * @dev Costruttore del contratto.
     * @param _rewardRate Tasso di ricompensa annuale per lo staking.
     */
    constructor(uint256 _rewardRate) ERC20("PingPongPlay", "PINGPP") {
        require(_rewardRate > 0, "Reward rate must be greater than 0");
        
        rewardRate = _rewardRate;
        
        _mint(address(this), TOTAL_SUPPLY);
        
        vestingStart = block.timestamp;

        // Distribuzione iniziale
        _transfer(address(this), msg.sender, PUBLIC_SALE); // Vendita pubblica
        _transfer(address(this), address(this), TEAM_FOUNDERS); // Token del team mantenuti nel contratto
        _transfer(address(this), msg.sender, MARKETING_PARTNERSHIP);
        _transfer(address(this), msg.sender, PROJECT_DEVELOPMENT);
        _transfer(address(this), msg.sender, RESERVE);
        _transfer(address(this), msg.sender, COMMUNITY_REWARDS);
    }

    /**
     * @dev Aggiorna il tasso di ricompensa per lo staking.
     * @param _newRate Nuovo tasso di ricompensa annuale.
     */
    function updateRewardRate(uint256 _newRate) external onlyOwner {
        require(_newRate > 0, "Reward rate must be greater than 0");
        rewardRate = _newRate;
    }

    /**
     * @dev Rilascia i token del team secondo il piano di vesting.
     */
    function releaseTeamTokens() external nonReentrant onlyOwner {
        require(block.timestamp >= vestingStart, "Vesting not started");
        
        uint256 elapsed = block.timestamp.sub(vestingStart);
        uint256 totalReleasable = TEAM_FOUNDERS.mul(elapsed).div(VESTING_DURATION);
        uint256 amountToRelease = totalReleasable.sub(teamReleased);

        require(amountToRelease > 0, "No tokens to release");

        teamReleased = teamReleased.add(amountToRelease);
        _transfer(address(this), owner(), amountToRelease);
    }

    /**
     * @dev Permette agli utenti di mettere in staking i propri token.
     * @param amount Quantità di token da mettere in staking.
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0 tokens");
        _transfer(msg.sender, address(this), amount);

        Stake storage userStake = stakes[msg.sender];
        stakeAddresses.push(msg.sender);

        // Calcola e rilascia gli interessi accumulati
        uint256 pendingReward = calculateReward(msg.sender);
        if (pendingReward > 0) {
            _transfer(address(this), msg.sender, pendingReward);
            emit InterestClaimed(msg.sender, pendingReward);
        }

        // Aggiorna lo stake e l'ultimo giorno in cui sono stati rilasciati gli interessi
        userStake.amount = userStake.amount.add(amount);
        userStake.timestamp = block.timestamp;
        userStake.lastClaimed = block.timestamp;
    }

    /**
     * @dev Permette agli utenti di ritirare i propri token in staking e le ricompense accumulate.
     * @param amount Quantità di token da ritirare.
     */
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot unstake 0 tokens");
        require(stakes[msg.sender].amount >= amount, "Insufficient staked amount");

        // Calcola gli interessi accumulati
        uint256 reward = calculateReward(msg.sender);
        uint256 totalAmount = amount.add(reward);

        // Aggiorna lo stake
        stakes[msg.sender].amount = stakes[msg.sender].amount.sub(amount);
        stakes[msg.sender].timestamp = block.timestamp;
        stakes[msg.sender].lastClaimed = block.timestamp;

        // Rilascia i token e gli interessi
        _transfer(address(this), msg.sender, totalAmount);
        
        // rimuove l'indirizzo dalla lista degli stakers
        for (uint i = 0; i < stakeAddresses.length; i++) {
            if (stakeAddresses[i] == msg.sender) {
                stakeAddresses[i] = stakeAddresses[stakeAddresses.length - 1];
                stakeAddresses.pop();
                break;
            }
        }


        emit Unstaked(msg.sender, amount);
        emit InterestClaimed(msg.sender, reward);
    }

    /**
     * @dev Calcola la ricompensa accumulata per un indirizzo staker.
     * @param staker Indirizzo dello staker.
     * @return Ricompensa accumulata.
     */
    function calculateReward(address staker) public view returns (uint256) {
        Stake memory userStake = stakes[staker];
        if (userStake.amount == 0) return 0;

        uint256 daysStaked = (block.timestamp - userStake.lastClaimed) / 1 days;
        uint256 annualReward = userStake.amount.mul(rewardRate).div(100);
        return annualReward.mul(daysStaked).div(365);
    }

    /**
     * @dev Rilascia tutti gli interessi maturati per ogni utente che ha stake attivo.
     */
    function releaseAllInterest() external onlyOwner {
        address[] memory stakers = _getAllStakers();
        uint256 totalReleased = 0;

        for (uint256 i = 0; i < stakers.length; i++) {
            Stake storage userStake = stakes[stakers[i]];
            uint256 pendingReward = calculateReward(stakers[i]);
            if (pendingReward > 0) {
                _transfer(address(this), stakers[i], pendingReward);
                userStake.lastClaimed = block.timestamp;  // Aggiorna l'ultimo giorno di rilascio
                totalReleased = totalReleased.add(pendingReward);
                emit InterestClaimed(stakers[i], pendingReward);
            }
        }
        
        emit AllInterestReleased(totalReleased);
    }

    // Funzione di supporto per ottenere l'elenco degli staker
    function _getAllStakers() internal view returns (address[] memory) {
        uint256 stakerCount = 0;
        for (uint i = 0; i < stakeAddresses.length; i++) {
            if (stakes[stakeAddresses[i]].amount > 0) { // corrected line here!
                stakerCount++;
            }
        }
        address[] memory stakers = new address[](stakerCount);
        uint256 index = 0;
        for (uint i = 0; i < stakeAddresses.length; i++) {
            if (stakes[stakeAddresses[i]].amount > 0) {
                stakers[index] = stakeAddresses[i];
                index++;
            }
        }
        return stakers;
    }

    // Eventi per tracciare le azioni di staking e ricompensa
    event InterestClaimed(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event AllInterestReleased(uint256 totalAmount);
}
