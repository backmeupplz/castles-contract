//  ░▒▓██████▓▒░ ░▒▓██████▓▒░ ░▒▓███████▓▒░▒▓████████▓▒░▒▓█▓▒░      ░▒▓████████▓▒░░▒▓███████▓▒░
// ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░   ░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░
// ░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░         ░▒▓█▓▒░   ░▒▓█▓▒░      ░▒▓█▓▒░      ░▒▓█▓▒░
// ░▒▓█▓▒░      ░▒▓████████▓▒░░▒▓██████▓▒░   ░▒▓█▓▒░   ░▒▓█▓▒░      ░▒▓██████▓▒░  ░▒▓██████▓▒░
// ░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░  ░▒▓█▓▒░   ░▒▓█▓▒░      ░▒▓█▓▒░             ░▒▓█▓▒░
// ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░  ░▒▓█▓▒░   ░▒▓█▓▒░      ░▒▓█▓▒░             ░▒▓█▓▒░
//  ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓███████▓▒░   ░▒▓█▓▒░   ░▒▓████████▓▒░▒▓████████▓▒░▒▓███████▓▒░

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Castles is Ownable, ReentrancyGuard {
  // Data structures
  struct Castle {
    uint256 balance;
    mapping(address => uint256) contributions;
  }
  struct Round {
    Castle northCastle;
    Castle southCastle;
    uint256 startBlock;
    uint256 endBlock;
  }
  enum CastleName {
    North,
    South
  }
  enum Winner {
    North,
    South,
    Draw
  }

  // State

  mapping(uint256 => Round) rounds;
  uint256 public currentRoundId;
  uint256 public roundDuration = 43200 * 3;
  uint256 public maxFee = 10;

  // Events

  event Defended(
    uint256 roundId,
    address indexed defender,
    uint256 amount,
    CastleName castle,
    address indexed ref
  );
  event Withdrawn(uint256 roundId, address indexed defender, uint256 amount);
  event RoundStarted(uint256 roundId, uint256 startBlock, uint256 endBlock);
  event RoundDurationSet(uint256 duration);
  event MaxFeeSet(uint256 fee);

  // Constructor

  constructor(address initialOwner) Ownable(initialOwner) {
    startNewRound();
  }

  // Setters

  function setRoundDuration(uint256 duration) public onlyOwner {
    roundDuration = duration;
    emit RoundDurationSet(duration);
  }

  function setMaxFee(uint256 fee) public onlyOwner {
    maxFee = fee;
    emit MaxFeeSet(fee);
  }

  // Getters

  function getRound(
    uint256 roundId
  )
    public
    view
    returns (
      uint256 startBlock,
      uint256 endBlock,
      uint256 northBalance,
      uint256 southBalance
    )
  {
    Round storage round = rounds[roundId];
    return (
      round.startBlock,
      round.endBlock,
      round.northCastle.balance,
      round.southCastle.balance
    );
  }

  function getContributions(
    uint256 roundId,
    address contributor
  )
    public
    view
    returns (uint256 northContributions, uint256 southContributions)
  {
    Round storage round = rounds[roundId];
    return (
      round.northCastle.contributions[contributor],
      round.southCastle.contributions[contributor]
    );
  }

  // Modifiers

  modifier onlyAfterRound(uint256 roundId) {
    require(block.number >= rounds[roundId].endBlock, "Round not finished yet");
    _;
  }

  // Functions

  function defend(
    CastleName castleName,
    address ref
  ) public payable nonReentrant {
    if (block.number >= rounds[currentRoundId].endBlock) {
      startNewRound();
    }

    uint256 amount = msg.value;

    uint256 feePercentage = calculateFeePercentage();
    uint256 feeAmount = (amount * feePercentage) / 100;
    uint256 netAmount = amount - feeAmount;

    if (ref != address(0)) {
      uint256 halfFee = feeAmount / 2;
      payable(ref).transfer(halfFee);
      payable(owner()).transfer(halfFee);
    } else {
      payable(owner()).transfer(feeAmount);
    }

    Castle storage castle = castleName == CastleName.North
      ? rounds[currentRoundId].northCastle
      : rounds[currentRoundId].southCastle;

    castle.balance += netAmount;
    castle.contributions[msg.sender] += netAmount;

    emit Defended(currentRoundId, msg.sender, amount, castleName, ref);
  }

  function withdraw(
    uint256 roundId
  ) public nonReentrant onlyAfterRound(roundId) {
    Round storage round = rounds[roundId];

    Winner winner = round.northCastle.balance > round.southCastle.balance
      ? Winner.North
      : round.northCastle.balance < round.southCastle.balance
      ? Winner.South
      : Winner.Draw;

    if (winner == Winner.Draw) {
      uint256 totalAmount = round.northCastle.contributions[msg.sender] +
        round.southCastle.contributions[msg.sender];
      round.northCastle.contributions[msg.sender] = 0;
      round.southCastle.contributions[msg.sender] = 0;
      payable(msg.sender).transfer(totalAmount);

      emit Withdrawn(roundId, msg.sender, totalAmount);
    } else {
      Castle storage winningCastle = winner == Winner.North
        ? round.northCastle
        : round.southCastle;
      Castle storage losingCastle = winner == Winner.North
        ? round.southCastle
        : round.northCastle;

      require(winningCastle.balance > 0, "The winning castle has no balance");

      uint256 winningAmount = winningCastle.contributions[msg.sender];
      require(
        winningAmount > 0,
        "You have no contributions to the winning castle"
      );

      // Improve precision by scaling up before dividing
      uint256 totalAmount = (((winningAmount * 1e18) / winningCastle.balance) *
        losingCastle.balance) /
        1e18 +
        winningAmount;

      winningCastle.contributions[msg.sender] = 0;

      payable(msg.sender).transfer(totalAmount);

      emit Withdrawn(roundId, msg.sender, totalAmount);
    }
  }

  // Helpers

  function calculateFeePercentage() public view returns (uint256) {
    uint256 blocksElapsed = block.number - rounds[currentRoundId].startBlock;
    if (blocksElapsed >= roundDuration) {
      return maxFee;
    }
    return (maxFee * blocksElapsed) / roundDuration;
  }

  function startNewRound() private {
    currentRoundId++;
    rounds[currentRoundId].startBlock = block.number;
    rounds[currentRoundId].endBlock = block.number + roundDuration;
    emit RoundStarted(
      currentRoundId,
      block.number,
      block.number + roundDuration
    );
  }
}
