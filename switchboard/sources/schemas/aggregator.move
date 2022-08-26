module switchboard::aggregator {
    use aptos_framework::timestamp;
    use switchboard::math::{Self, SwitchboardDecimal};
    use switchboard::vec_utils;
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;


    struct AggregatorRound has store, copy, drop {
        // Maintains the time that the round was opened at.
        round_open_timestamp: u64,
        // Maintains the current median of all successful round responses.
        result: SwitchboardDecimal,
        // Standard deviation of the accepted results in the round.
        std_deviation: SwitchboardDecimal,
        // Maintains the minimum node response this round.
        min_response: SwitchboardDecimal,
        // Maintains the maximum node response this round.
        max_response: SwitchboardDecimal,
        // Pubkeys of the oracles fulfilling this round.
        oracle_keys: vector<address>,
        // Represents all successful node responses this round. `NaN` if empty.
        medians: vector<Option<SwitchboardDecimal>>,
        // Current rewards/slashes oracles have received this round.
        current_payout: vector<SwitchboardDecimal>,
        // could do specific error codes
        errors_fulfilled: vector<bool>,
        // Maintains the number of successful responses received from nodes.
        // Nodes can submit one successful response per round.
        num_success: u64,
        num_error: u64,
    }

    public fun default_round(): AggregatorRound {
        AggregatorRound {
            round_open_timestamp: 0,
            result: math::zero(),
            std_deviation: math::zero(),
            min_response: math::zero(),
            max_response: math::zero(),
            oracle_keys: vector::empty(),
            medians: vector::empty(),
            current_payout: vector::empty(),
            errors_fulfilled: vector::empty(),
            num_error: 0,
            num_success: 0,
        }
    }

    struct Aggregator has key, store, drop {
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        // CONFIGS
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,  // timestamp to start feed updates at
        variance_threshold: SwitchboardDecimal,
        force_report_period: u64, // If no feed results after this period, trigger nodes to report
        expiration: u64,
        //
        next_allowed_update_time: u64,
        is_locked: bool,
        crank_address: address,
        latest_confirmed_round: AggregatorRound,
        current_round: AggregatorRound,
        job_keys: vector<address>,
        job_weights: vector<u8>,
        jobs_checksum: vector<u8>, // Used to confirm with oracles they are answering what they think theyre answering
        //
        authority: address,
        /* history_buffer: vector<u8>, */
        disable_crank: bool,
        created_at: u64,
        crank_row_count: u64,
    }

    struct AggregatorConfigParams has drop, copy {
        addr: address,
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,
        variance_threshold: SwitchboardDecimal,
        force_report_period: u64,
        expiration: u64,
        authority: address,
    }

    public fun addr_from_conf(conf: &AggregatorConfigParams): address {
        conf.addr
    }

    public fun queue_from_conf(conf: &AggregatorConfigParams): address {
        conf.queue_address
    }

    public fun new_config(
        addr: address,
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,
        variance_threshold: SwitchboardDecimal,
        force_report_period: u64,
        expiration: u64,
        authority: address,
    ): AggregatorConfigParams {
        AggregatorConfigParams {
            addr,
            name,
            metadata,
            queue_address,
            batch_size,
            min_oracle_results,
            min_job_results,
            min_update_delay_seconds,
            start_after,
            variance_threshold,
            force_report_period,
            expiration,
            authority,
        }
    }

    public(friend) fun exist(addr: address): bool {
        exists<Aggregator>(addr)
    }

    public(friend) fun has_authority(addr: address, account: &signer): bool acquires Aggregator {
        let ref = borrow_global<Aggregator>(addr);
        ref.authority == signer::address_of(account)
    }

    public(friend) fun aggregator_create(account: &signer, aggregator: Aggregator) {
        move_to(account, aggregator);
    }

    public fun new(params: AggregatorConfigParams): Aggregator {
        Aggregator {
            name: params.name,
            metadata: params.metadata,
            queue_address: params.queue_address,
            batch_size: params.batch_size,
            min_oracle_results: params.min_oracle_results,
            min_job_results: params.min_job_results,
            min_update_delay_seconds: params.min_update_delay_seconds,
            start_after: params.start_after,
            variance_threshold: params.variance_threshold,
            force_report_period: params.force_report_period,
            expiration: params.expiration,
            /* consecutive_failure_count: 0, */
            next_allowed_update_time: 0,
            is_locked: false,
            crank_address: @0x0,
            latest_confirmed_round: default_round(),
            current_round: default_round(),
            job_keys: vector::empty(),
            jobs_checksum: vector::empty(),
            authority: params.authority,
            /* history: todo */
            disable_crank: false,
            job_weights: vector::empty(),
            created_at: timestamp::now_seconds(),
            crank_row_count: 0,
        }
    }

    public fun set_config(params: &AggregatorConfigParams) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(params.addr);
        aggregator.name = params.name;
        aggregator.metadata = params.metadata;
        aggregator.queue_address = params.queue_address;
        aggregator.batch_size = params.batch_size;
        aggregator.min_oracle_results = params.min_oracle_results;
        aggregator.min_job_results = params.min_job_results;
        aggregator.min_update_delay_seconds = params.min_update_delay_seconds;
        aggregator.start_after = params.start_after;
        aggregator.variance_threshold = params.variance_threshold;
        aggregator.force_report_period = params.force_report_period;
        aggregator.expiration = params.expiration;
        aggregator.authority = params.authority;
    }

    public(friend) fun set_crank(addr: address, crank_addr: address) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        aggregator.crank_address = crank_addr;
    }

    public(friend) fun add_crank_row_count(self: address) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(self);
        aggregator.crank_row_count = aggregator.crank_row_count + 1;
    }

    public(friend) fun sub_crank_row_count(self: address) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(self);
        aggregator.crank_row_count = aggregator.crank_row_count - 1;
    }

    public(friend) fun apply_oracle_error(addr: address, oracle_idx: u64) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        aggregator.current_round.num_error = aggregator.current_round.num_error + 1;
        let val_ref = vector::borrow_mut(&mut aggregator.current_round.errors_fulfilled, oracle_idx);
        *val_ref = true
    }

    public(friend) fun lock(aggregator: &mut Aggregator) {
        aggregator.is_locked = true;
    }

    public(friend) fun open_round(self: address, oracle_keys: &vector<address>) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(self);
        let size = aggregator.batch_size;
        aggregator.current_round = default_round();
        aggregator.current_round.round_open_timestamp = timestamp::now_seconds();
        aggregator.current_round.oracle_keys = *oracle_keys; // OracleQueue::next_n(queue, size);
        aggregator.current_round.medians = vec_utils::new_sized(size, option::none());
        aggregator.current_round.errors_fulfilled = vec_utils::new_sized(size, false);
        aggregator.next_allowed_update_time = timestamp::now_seconds() + aggregator.min_update_delay_seconds;
    }
    
    public(friend) fun save_result(
        aggregator_addr: address, 
        oracle_idx: u64, 
        value: &SwitchboardDecimal,
        min_response: &SwitchboardDecimal,
        max_response: &SwitchboardDecimal,
    ): bool acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(aggregator_addr);
        let val_ref = vector::borrow_mut(&mut aggregator.current_round.medians, oracle_idx);
        *val_ref = option::some(*value);
        let uwm = vec_utils::unwrap(&aggregator.current_round.medians);
        aggregator.current_round.result = math::median_mut(&mut uwm);
        if (math::gt(&aggregator.current_round.min_response, min_response)){
            aggregator.current_round.min_response = *min_response;
        };
        if (math::lt(&aggregator.current_round.max_response, max_response)){
            aggregator.current_round.max_response = *max_response;
        };
        aggregator.current_round.num_success = aggregator.current_round.num_success + 1;
        aggregator.current_round.std_deviation = math::std_deviation(&uwm, &aggregator.current_round.result);
        if (aggregator.current_round.num_success >= aggregator.min_oracle_results) {
            aggregator.latest_confirmed_round = aggregator.current_round;
            return true
        }; 

        false
    }

    // GETTERS 
    public fun latest_value(addr: address): SwitchboardDecimal acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        
        // grab a copy of latest result
        aggregator.latest_confirmed_round.result
    }

    public fun next_allowed_timestamp(addr: address): u64 acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.next_allowed_update_time
    }

    public fun job_keys(addr: address): vector<address> acquires Aggregator {
        borrow_global<Aggregator>(addr).job_keys
    }

    public fun min_oracle_results(addr: address): u64 acquires Aggregator {
        borrow_global<Aggregator>(addr).min_oracle_results
    }

    public fun crank_address(addr: address): address acquires Aggregator {
        borrow_global<Aggregator>(addr).crank_address
    }

    public fun crank_disabled(addr: address): bool acquires Aggregator {
        borrow_global<Aggregator>(addr).disable_crank
    }

    public(friend) fun crank_row_count(self: address): u64 acquires Aggregator {
        borrow_global<Aggregator>(self).crank_row_count
    }

    public fun current_round_num_success(addr: address): u64 acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.current_round.num_success
    }

    public fun current_round_num_error(addr: address): u64 acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.current_round.num_error
    }

    public fun curent_round_oracle_key_at_idx(addr: address, idx: u64): address acquires Aggregator {
        *vector::borrow(&borrow_global<Aggregator>(addr).current_round.oracle_keys, idx)
    }
    
    public fun current_round_std_dev(addr: address): SwitchboardDecimal acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.current_round.std_deviation
    }

    public fun current_round_result(addr: address): SwitchboardDecimal acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.current_round.result
    }

    public fun is_median_fulfilled(addr: address, idx: u64): bool acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        let val = vector::borrow(&aggregator.current_round.medians, idx);
        option::is_some(val)
    }

    public fun is_error_fulfilled(addr: address, idx: u64): bool acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        *vector::borrow(&aggregator.current_round.errors_fulfilled, idx)
    }

    public fun batch_size(self: address): u64 acquires Aggregator {
        borrow_global_mut<Aggregator>(self).batch_size
    }
    
    public fun queue(addr: address): address acquires Aggregator {
        borrow_global<Aggregator>(addr).queue_address
    }

    public fun can_open_round(addr: address): bool acquires Aggregator {
        let ref = borrow_global<Aggregator>(addr);
        timestamp::now_seconds() >= ref.next_allowed_update_time
    }

    public fun is_jobs_checksum_equal(addr: address, vec: &vector<u8>): bool acquires Aggregator {
        let checksum = borrow_global<Aggregator>(addr).jobs_checksum; // copy
        let i = 0;
        let size = vector::length(&checksum);
        while (i < size) {
            let left_byte = *vector::borrow(&checksum, i);
            let right_byte = *vector::borrow(vec, i);
            if (left_byte != right_byte) {
                return false
            };
            i = i + 1;
        };
        true
    }

    public entry fun new_test(account: &signer, value: u128, dec: u8, sign: bool) {
        let aggregator = Aggregator {
            name: vector::empty(),
            metadata: vector::empty(),
            queue_address: @0x55,
            batch_size: 3,
            min_oracle_results: 1,
            min_job_results: 1,
            min_update_delay_seconds: 5,
            start_after: 0,
            variance_threshold: math::new(0, 0, false),
            force_report_period: 0, 
            expiration: 0,
            next_allowed_update_time: 0,
            is_locked: false,
            crank_address: @0x55,
            latest_confirmed_round: AggregatorRound {
                round_open_timestamp: 0,
                result: math::new(value, dec, sign),
                std_deviation: math::new(3141592653, 9, false),
                min_response: math::new(3141592653, 9, false),
                max_response: math::new(3141592653, 9, false),
                oracle_keys: vector::empty(),
                medians: vector::empty(),
                current_payout: vector::empty(),
                errors_fulfilled: vector::empty(),
                num_success: 0,
                num_error: 0,
            },
            current_round: AggregatorRound {
                round_open_timestamp: 0,
                result: math::zero(),
                std_deviation: math::zero(),
                min_response: math::zero(),
                max_response: math::zero(),
                oracle_keys: vector::empty(),
                medians: vector::empty(),
                current_payout: vector::empty(),
                errors_fulfilled: vector::empty(),
                num_success: 0,
                num_error: 0,
            },
            job_keys: vector::empty(),
            job_weights: vector::empty(),
            jobs_checksum: vector::empty(),
            authority: @0x55,
            disable_crank: false,
            created_at: 0,
            crank_row_count: 0,
        };

        move_to<Aggregator>(account, aggregator);
    }

    public entry fun update_value(account: &signer, value: u128, dec: u8, neg: bool) acquires Aggregator {
        let ref = borrow_global_mut<Aggregator>(signer::address_of(account));
        ref.latest_confirmed_round.result = math::new(value, dec, neg);
    }
}
