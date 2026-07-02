// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// -----------------------------------------------------------------------------+
// WarmyToken
// -----------------------------------------------------------------------------+


contract WarmyToken {
    string public constant name = "WARMY";
    string public constant symbol = "WARMY";
    uint8 public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address initialHolder) {
        require(initialHolder != address(0), "WarmyToken: zero holder");
        balanceOf[initialHolder] = TOTAL_SUPPLY;
        emit Transfer(address(0), initialHolder, TOTAL_SUPPLY);
    }

    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 current = allowance[from][msg.sender];
        require(current >= amount, "WarmyToken: allowance");
        unchecked {
            allowance[from][msg.sender] = current - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != address(0), "WarmyToken: zero to");
        uint256 fromBal = balanceOf[from];
        require(fromBal >= amount, "WarmyToken: balance");
        unchecked {
            balanceOf[from] = fromBal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}

// -----------------------------------------------------------------------------+
// WarmyVesting
// -----------------------------------------------------------------------------+

/**
 * @title WarmyVesting
 */
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

    function allocationTotal() external view returns (uint256) {
        return tgeAmount + linearAmount;
    }

    function releasableAt(uint256 timestamp) public view returns (uint256) {
        if (timestamp < start) {
            return 0;
        }

        uint256 gross = 0;
        unchecked {
            gross += tgeAmount;
        }

        if (linearAmount > 0) {
            uint256 cliffEnd = uint256(start) + uint256(cliffDuration);
            if (timestamp > cliffEnd) {
                uint256 elapsed = timestamp - cliffEnd;
                if (elapsed >= linearDuration) {
                    gross += linearAmount;
                } else {
                    gross += (linearAmount * elapsed) / uint256(linearDuration);
                }
            }
        }

        uint256 bal = token.balanceOf(address(this));
        if (gross > bal) {
            gross = bal;
        }
        return gross;
    }

    function releasable() external view returns (uint256) {
        uint256 gross = releasableAt(block.timestamp);
        if (gross <= released) {
            return 0;
        }
        return gross - released;
    }

    function release() external {
        uint256 gross = releasableAt(block.timestamp);
        require(gross > released, "Vesting: nothing");
        uint256 amount = gross - released;
        released = gross;
        require(token.transfer(beneficiary, amount), "Vesting: transfer");
        emit Released(beneficiary, amount, released);
    }
}