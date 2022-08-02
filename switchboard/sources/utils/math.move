module Switchboard::Math {

    use Switchboard::VecUtils;
    use std::vector;
    use std::error;

    const EINCORRECT_STD_DEV: u64 = 0;
    const ENO_LENGTH_PASSED_IN_STD_DEV: u64 = 1;
    const EMORE_THAN_18_DECIMALS: u64 = 2;
    const MAX_DECIMALS: u8 = 9;
    const POW_10_TO_MAX_DECIMALS: u128 = 1000000000;
    const U128_MAX: u128 = 340282366920938463463374607431768211455;
    const MAX_VALUE_ALLOWED: u128 = 340282366920938463463374607431;

    struct Num has copy, drop, store { value: u128, dec: u8, neg: bool }

    public fun max_u128(): u128 {
        U128_MAX
    }

    public fun num(value: u128, dec: u8, neg: bool): Num {
        assert!(
            dec <= MAX_DECIMALS,
            EMORE_THAN_18_DECIMALS
        );
        let num = Num { value, dec, neg };
        normalize(&mut num);
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

    public fun num_unpack(num: Num): (u128, u8, bool) {
        let Num { value, dec, neg } = num;
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

    public fun zero(): Num {
      Num {
        value: 0,
        dec: 0,
        neg: false
      }
    }

    // TODO: get weighted median
    public fun median(v: &vector<Num>): Num {
        let v = sort(v);
        *vector::borrow(&v, vector::length(&v) / 2)
    }

    public fun std_deviation(medians: &vector<Num>): Num {
        let median = median(medians);

        // length of decimals
        let length = vector::length<Num>(medians);

        // check that there are medians passed in
        assert!(length != 0, error::internal(ENO_LENGTH_PASSED_IN_STD_DEV));

        // zero out response
        let res = zero();
        let distance = zero();
        let variance = zero();

        let i = 0;
        while (i < length) {

            // get median i
            let median_i = vector::borrow<Num>(medians, i);

            // subtract the median from the result
            sub(median_i, &median, &mut distance);

            // square res (copies on each operation)
            mul(
                &distance, 
                &distance,
                &mut variance
            );

            // add distance to res, write it to distance
            add(&res, &variance, &mut distance);
            res.value = distance.value;
            res.dec = distance.dec;
            res.neg = distance.neg;

            // iterate
            i = i + 1;
        };

        // divide by length
        div(&res, &num((length as u128), 0, false), &mut distance);

        // get sqrt
        sqrt(&distance, &mut res);

        res
    }

    public fun sort(v: &vector<Num>): vector<Num> {
        let size = vector::length(v);
        let alloc = vector::empty();
        if (size <= 1) {
            return *v
        };

        let (left, right) = VecUtils::esplit(v);
        let left = sort(&left);
        let right = sort(&right);
   

        loop {
            let left_len = vector::length<Num>(&left);
            let right_len = vector::length<Num>(&right);
            if (left_len != 0 && right_len != 0) {
                // TODO: play with reversing to switch remove with pop_back
                if (gt(vector::borrow<Num>(&right, 0), vector::borrow<Num>(&left, 0))) {
                   vector::push_back<Num>(&mut alloc, vector::remove<Num>(&mut left, 0));
                } else {
                    vector::push_back<Num>(&mut alloc, vector::remove<Num>(&mut right, 0));
                }
            } else if (left_len != 0) {
                vector::push_back<Num>(&mut alloc, vector::remove<Num>(&mut left, 0));
            } else if (right_len != 0) {
                vector::push_back<Num>(&mut alloc, vector::remove<Num>(&mut right, 0));
            } else {
                return alloc
            };
        }
    }

    // By reference 

    fun abs_gt(val1: &Num, val2: &Num): bool {
        let max_dec = max(val1.dec, val2.dec);
        let num1_scaled = val1.value * pow_10(max_dec - val1.dec);
        let num2_scaled = val2.value * pow_10(max_dec - val2.dec);
        num1_scaled > num2_scaled
    }

    fun abs_lt(val1: &Num, val2: &Num): bool {

        let max_dec = max(val1.dec, val2.dec);
        let num1_scaled = val1.value * pow_10(max_dec - val1.dec);
        let num2_scaled = val2.value * pow_10(max_dec - val2.dec);
        num1_scaled < num2_scaled
    }

    public fun add(val1: &Num, val2: &Num, out: &mut Num) {
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

    fun add_internal(val1: &Num, val2: &Num, out: &mut Num) {
        let max_dec = max(val1.dec, val2.dec);
        let num1_scaled = val1.value * pow_10(max_dec - val1.dec);
        let num2_scaled = val2.value * pow_10(max_dec - val2.dec);
        out.value = num1_scaled + num2_scaled;
        out.dec = max_dec;
        out.neg = false;
    }

    public fun sub(val1: &Num, val2: &Num, out: &mut Num) {
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

    fun sub_internal(val1: &Num, val2: &Num, out: &mut Num) {

        let max_dec = max(val1.dec, val2.dec);
        let num1_scaled = val1.value * pow_10(max_dec - val1.dec);
        let num2_scaled = val2.value * pow_10(max_dec - val2.dec);

        if (num2_scaled > num1_scaled) {
            out.value = (num2_scaled - num1_scaled);
            out.dec = max_dec;
            out.neg = true;
        } else {
            out.value = (num1_scaled - num2_scaled);
            out.dec = max_dec;
            out.neg = false;
        };
    }


    public fun mul(val1: &Num, val2: &Num, out: &mut Num) {
        let neg = !((val1.neg && val2.neg) || (!val1.neg && !val2.neg));
        mul_internal(val1, val2, out);
        out.neg = neg;
    }

    fun mul_internal(val1: &Num, val2: &Num, out: &mut Num) {
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

    public fun div(val1: &Num, val2: &Num, out: &mut Num) {
        one_over(val2, out);
        let one_over = *out; // copy out
        mul(val1, &one_over, out);
    }

    fun one_over(val2: &Num, out: &mut Num) {
        let num1_scaled = POW_10_TO_MAX_DECIMALS;
        out.value = num1_scaled / val2.value;
        out.dec = MAX_DECIMALS - val2.dec;
        out.neg = val2.neg;
    }

    // babylonian
    public fun sqrt(num: &Num, out: &mut Num) {
        let y = num;

        // z = y
        out.value = y.value;
        out.neg = y.neg;
        out.dec = y.dec;

        // intermediate variables for outputs
        let out1 = zero();
        let out2 = zero();

        let two = num(2, 0, false);
        let one = num(1, 0, false);

        let x = zero();

        // x = y / 2 + 1
        div_original(y, &two, &mut out1);
        add(&out1, &one, &mut x);

        // x < z && x != y
        while (gt(out, &x) && x.value != 0 || equals(&x, y)) {
            out.value = x.value;
            out.dec = x.dec;
            out.neg = x.neg; 

            // x = (x + (y / x))) * 0.5
            div_original(y, &x, &mut out1);
            add(&out1, &x, &mut out2);
            div_original(&out2, &two, &mut x);
        }
    }

    public fun normalize(num: &mut Num) {
        while (num.value % 10 == 0 && num.dec > 0) {
            num.value = num.value / 10;
            num.dec = num.dec - 1;
        };
    }

    public fun div_original(val1: &Num, val2: &Num, out: &mut Num) {
        let neg = !((val1.neg && val2.neg) || (!val1.neg && !val2.neg));
        let num1_scaling_factor = pow_10(MAX_DECIMALS - val1.dec);
        let num1_scaled = val1.value * num1_scaling_factor;
        let num1_scaled_with_overflow = num1_scaled * POW_10_TO_MAX_DECIMALS;
        let num2_scaling_factor = pow_10(MAX_DECIMALS - val2.dec);
        let num2_scaled = val2.value * num2_scaling_factor;
        out.value = num1_scaled_with_overflow / num2_scaled;
        out.dec = MAX_DECIMALS;
        out.neg = neg;
    }

    public fun gt(val1: &Num, val2: &Num): bool {
        let max_dec = max(val1.dec, val2.dec);
        let num1_scaled = val1.value * pow_10(max_dec - val1.dec);
        let num2_scaled = val2.value * pow_10(max_dec - val2.dec);
        if (val1.neg && val2.neg) {
            return num1_scaled < num2_scaled
        } else if (val1.neg) {
            return false
        } else if (val2.neg) {
            return true
        };
        num1_scaled > num2_scaled
    }

    public fun lt(val1: &Num, val2: &Num): bool {
        let max_dec = max(val1.dec, val2.dec);
        let num1_scaled = val1.value * pow_10(max_dec - val1.dec);
        let num2_scaled = val2.value * pow_10(max_dec - val2.dec);
        if (val1.neg && val2.neg) {
            return num1_scaled > num2_scaled
        } else if (val1.neg) {
            return true
        } else if (val2.neg) {
            return false
        };
        num1_scaled < num2_scaled
    }


    public fun equals(val1: &Num, val2: &Num): bool {
        let num1 = scale_to_decimals(val1, MAX_DECIMALS);
        let num2 = scale_to_decimals(val2, MAX_DECIMALS);
        num1 == num2 && val1.neg == val2.neg
    }

    public fun scale_to_decimals(num: &Num, scale_dec: u8): u128 {
        if (num.dec < scale_dec) {
            return (num.value * pow_10(scale_dec - num.dec))
        } else {
            return (num.value / pow_10(num.dec - scale_dec))
        }
    }

    #[test(account = @0x1)]
    public entry fun test_math() {

        let vec = vector::empty<Num>();

        // inputs are value, scale factor
        let decimal1 = num(10, 0, false);
        let decimal2 = num(11, 0, false);
        let decimal3 = num(12, 0, false);
        let decimal4 = num(13, 0, false);
        let decimal5 = num(14, 0, false);

        // push the decimal
        vector::push_back<Num>(&mut vec, decimal1);
        vector::push_back<Num>(&mut vec, decimal2);
        vector::push_back<Num>(&mut vec, decimal3);
        vector::push_back<Num>(&mut vec, decimal4);
        vector::push_back<Num>(&mut vec, decimal5);

        // std_deviation
        let t1 = std_deviation(&vec);

        std::debug::print(&t1);

       // let out = zero();
       // sqrt(&num(340282366920938463463374607431, 9, false), &mut out);
    }
}
