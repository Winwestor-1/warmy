// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract WarmyVesting {
    IERC20 public immutable token;
    address public immutable beneficiary;

    uint64 public immutable start;
    uint256 public immutable tgeAmount;
    uint64 public immutable cliffDuration;
    uint256 public immutable linearAmount;
    uint64 public immutable linearDuration;

    uint256 public released;

    event Released(address indexed to, uint256 amount, uint256 totalReleased);

    constructor(
        IERC20 token_,
        address beneficiary_,
        uint64 start_,
        uint256 tgeAmount_,
        uint64 cliffDuration_,
        uint256 linearAmount_,
        uint64 linearDuration_
    ) {
        require(address(token_) != address(0), "Vesting: zero token");
        require(beneficiary_ != address(0), "Vesting: zero beneficiary");
        require(tgeAmount_ + linearAmount_ > 0, "Vesting: zero allocation");
        if (linearAmount_ > 0) {
            require(linearDuration_ > 0, "Vesting: linear needs duration");
        } else {
            require(linearDuration_ == 0, "Vesting: linear duration");
        }

        token = token_;
        beneficiary = beneficiary_;
        start = start_;
        tgeAmount = tgeAmount_;
        cliffDuration = cliffDuration_;
        linearAmount = linearAmount_;
        linearDuration = linearDuration_;
    }

    /// @notice Sum of TGE + linear cap (for off-chain checks / funding).
    function allocationTotal() external view returns (uint256) {
        return tgeAmount + linearAmount;
    }

    /// @notice Vested amount per schedule only (not reduced by balance or prior releases).
    function vestedAmount(uint256 timestamp) public view returns (uint256) {
        if (timestamp < start) {
            return 0;
        }

        uint256 vested = 0;
        unchecked {
            vested += tgeAmount;
        }

        if (linearAmount > 0) {
            uint256 cliffEnd = uint256(start) + uint256(cliffDuration);
            if (timestamp > cliffEnd) {
                uint256 elapsed = timestamp - cliffEnd;
                if (elapsed >= linearDuration) {
                    vested += linearAmount;
                } else {
                    vested += (linearAmount * elapsed) / uint256(linearDuration);
                }
            }
        }

        return vested;
    }

    /// @notice Same as `vestedAmount` (schedule only). Use `releasable()` for what you can claim now.
    function releasableAt(uint256 timestamp) public view returns (uint256) {
        return vestedAmount(timestamp);
    }

    /// @notice Claimable now: schedule owed minus already released, capped by token balance in this contract.
    function releasable() public view returns (uint256) {
        uint256 vested = vestedAmount(block.timestamp);
        if (vested <= released) {
            return 0;
        }
        uint256 owed = vested - released;
        uint256 bal = token.balanceOf(address(this));
        return owed > bal ? bal : owed;
    }

    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "Vesting: nothing");
        released += amount;
        require(token.transfer(beneficiary, amount), "Vesting: transfer");
        emit Released(beneficiary, amount, released);
    }
}