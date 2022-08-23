module Switchboard::Math {

    use Switchboard::VecUtils;
    use std::vector;

    const EINCORRECT_STD_DEV: u64 = 0;
    const ENO_LENGTH_PASSED_IN_STD_DEV: u64 = 1;
    const EMORE_THAN_9_DECIMALS: u64 = 2;
    const EINPUT_TOO_LARGE: u64 = 3;

    const MAX_DECIMALS: u8 = 9;
    const POW_10_TO_MAX_DECIMALS: u128 = 1000000000;
    const U128_MAX: u128 = 340282366920938463463374607431768211455;
    const MAX_VALUE_ALLOWED: u128 = 340282366920938463463374607431;

    struct SwitchboardDecimal has copy, drop, store { value: u128, dec: u8, neg: bool }

    public fun max_u128(): u128 {
        U128_MAX
    }

    public fun num(value: u128, dec: u8, neg: bool): SwitchboardDecimal {
        assert!(
            dec <= MAX_DECIMALS,
            EMORE_THAN_9_DECIMALS
        );
        let num = SwitchboardDecimal { value, dec, neg };

        // expand nums out 
        num.value = scale_to_decimals(&num, MAX_DECIMALS);
        num.dec = MAX_DECIMALS;

        num
    }

    public fun pow(base: u64, exp: u8): u128 {
        let result_val = 1u128;
        let i = 0;
        while (i < exp) {
            result_val = result_val * (base as u128);
            i = i + 1;
        };
        result_val
    }

    public fun pow_10(exp: u8): u128 {
        pow(10, exp)
    }

    public fun num_unpack(num: SwitchboardDecimal): (u128, u8, bool) {
        let SwitchboardDecimal { value, dec, neg } = num;
        (value, dec, neg)
    }

    fun max(a: u8, b: u8): u8 {
        if (a > b) a else b
    }

    fun min(a: u8, b: u8): u8 {
        if (a > b) b else a
    }

    // abs(a - b)
    fun sub_abs_u8(a: u8, b: u8): u8 {
        if (a > b) {
            a - b
        } else {
            b - a
        }
    }

    public fun zero(): SwitchboardDecimal {
      SwitchboardDecimal {
        value: 0,
        dec: 0,
        neg: false
      }
    }

    // TODO: get weighted median
    public fun median(v: &vector<SwitchboardDecimal>): SwitchboardDecimal {
        let v = sort(v);
        *vector::borrow(&v, vector::length(&v) / 2)
    }

    public fun median_mut(v: &mut vector<SwitchboardDecimal>): SwitchboardDecimal {
        let size = vector::length(v);
        little_floyd_rivest(v, size / 2, 0, size - 1)
    }

    public fun std_deviation(medians: &vector<SwitchboardDecimal>, median: &SwitchboardDecimal): SwitchboardDecimal {
        assert!(vector::length(medians) > 0, 0);
        *median
    }

    public fun sort(v: &vector<SwitchboardDecimal>): vector<SwitchboardDecimal> {
        let size = vector::length(v);
        let alloc = vector::empty();
        if (size <= 1) {
            return *v
        };

        let (left, right) = VecUtils::esplit(v);
        let left = sort(&left);
        let right = sort(&right);
   

        loop {
            let left_len = vector::length<SwitchboardDecimal>(&left);
            let right_len = vector::length<SwitchboardDecimal>(&right);
            if (left_len != 0 && right_len != 0) {
                // TODO: play with reversing to switch remove with pop_back
                if (gt(vector::borrow<SwitchboardDecimal>(&right, 0), vector::borrow<SwitchboardDecimal>(&left, 0))) {
                   vector::push_back<SwitchboardDecimal>(&mut alloc, vector::remove<SwitchboardDecimal>(&mut left, 0));
                } else {
                    vector::push_back<SwitchboardDecimal>(&mut alloc, vector::remove<SwitchboardDecimal>(&mut right, 0));
                }
            } else if (left_len != 0) {
                vector::push_back<SwitchboardDecimal>(&mut alloc, vector::remove<SwitchboardDecimal>(&mut left, 0));
            } else if (right_len != 0) {
                vector::push_back<SwitchboardDecimal>(&mut alloc, vector::remove<SwitchboardDecimal>(&mut right, 0));
            } else {
                return alloc
            };
        }
    }

    // By reference 

    fun abs_gt(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal): bool {
        val1.value > val2.value
    }

    fun abs_lt(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal): bool {
        val1.value < val2.value
    }

    public fun add(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        // -x + -y
        if (val1.neg && val2.neg) {
            add_internal(val1, val2, out);
            out.neg = true;

        // -x + y
        } else if (val1.neg) {
            sub_internal(val2, val1, out);
            
        // x + -y
        } else if (val2.neg) {
            sub_internal(val1, val2, out);

        // x + y
        } else {
            add_internal(val1, val2, out);
        };
    }

    fun add_internal(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        out.value = val1.value + val2.value;
        out.dec = MAX_DECIMALS;
        out.neg = false;
    }

    public fun sub(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        // -x - -y
        if (val1.neg && val2.neg) {
            add_internal(val1, val2, out);
            out.neg = abs_gt(val1, val2);

        // -x - y
        } else if (val1.neg) {
            add_internal(val1, val2, out);
            out.neg = true;

        // x - -y
        } else if (val2.neg) {
            add_internal(val1, val2, out);

         // x - y
        } else {
            sub_internal(val1, val2, out);
        };
    }

    fun sub_internal(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        if (val2.value > val1.value) {
            out.value = (val2.value - val1.value);
            out.dec = MAX_DECIMALS;
            out.neg = true;
        } else {
            out.value = (val1.value - val2.value);
            out.dec = MAX_DECIMALS;
            out.neg = false;
        };
    }


    public fun mul(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        let neg = !((val1.neg && val2.neg) || (!val1.neg && !val2.neg));
        mul_internal(val1, val2, out);
        out.neg = neg;
    }

    fun mul_internal(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        let multiplied = val1.value * val2.value;
        let new_decimals = val1.dec + val2.dec;
        let multiplied_scaled = if (new_decimals < MAX_DECIMALS) {
            let decimals_underflow = MAX_DECIMALS - new_decimals;
            multiplied * pow_10(decimals_underflow)
        } else if (new_decimals > MAX_DECIMALS) {
            let decimals_overflow = new_decimals - MAX_DECIMALS;
            multiplied / pow_10(decimals_overflow)
        } else {
            multiplied
        };

        out.value = multiplied_scaled;
        out.dec = MAX_DECIMALS;
        out.neg = false;
    }

    public fun div(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        one_over(val2, out);
        let one_over = *out; // copy out
        mul(val1, &one_over, out);
    }

    fun one_over(val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        let num1_scaled = POW_10_TO_MAX_DECIMALS;
        out.value = num1_scaled / val2.value;
        out.dec = MAX_DECIMALS - val2.dec;
        out.neg = val2.neg;
    }

    public fun sqrt(num: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        let y = num;

        // z = y
        out.value = y.value;
        out.neg = y.neg;
        out.dec = y.dec;
    }

    public fun normalize(num: &mut SwitchboardDecimal) {
        while (num.value % 10 == 0 && num.dec > 0) {
            num.value = num.value / 10;
            num.dec = num.dec - 1;
        };
    }

    public fun div_original(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal, out: &mut SwitchboardDecimal) {
        let neg = !((val1.neg && val2.neg) || (!val1.neg && !val2.neg));
        let num1_scaled_with_overflow = val1.value * POW_10_TO_MAX_DECIMALS;
        out.value = num1_scaled_with_overflow / val2.value;
        out.dec = MAX_DECIMALS;
        out.neg = neg;
    }

    public fun gt(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal): bool {
        if (val1.neg && val2.neg) {
            return val1.value < val2.value
        } else if (val1.neg) {
            return false
        } else if (val2.neg) {
            return true
        };
        val1.value > val2.value
    }

    public fun lt(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal): bool {
       if (val1.neg && val2.neg) {
            return val1.value > val2.value
        } else if (val1.neg) {
            return true
        } else if (val2.neg) {
            return false
        };
        val1.value < val2.value
    }


    public fun equals(val1: &SwitchboardDecimal, val2: &SwitchboardDecimal): bool {
        let num1 = scale_to_decimals(val1, MAX_DECIMALS);
        let num2 = scale_to_decimals(val2, MAX_DECIMALS);
        num1 == num2 && val1.neg == val2.neg
    }

    public fun scale_to_decimals(num: &SwitchboardDecimal, scale_dec: u8): u128 {
        if (num.dec < scale_dec) {
            return (num.value * pow_10(scale_dec - num.dec))
        } else {
            return (num.value / pow_10(num.dec - scale_dec))
        }
    }
    
    public fun little_floyd_rivest(vec: &mut vector<SwitchboardDecimal>, k: u64, left: u64, right: u64): SwitchboardDecimal {
        let size = vector::length<SwitchboardDecimal>(vec);
        assert!(size < 600 && left + right == 0, EINPUT_TOO_LARGE);
        *vector::borrow(vec, k)
    }
}
