module switchboard::aggregator {
    use aptos_framework::timestamp;
    use switchboard::math::{Self, SwitchboardDecimal};
    use switchboard::errors;
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;
    use std::coin::{Self, Coin};

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
        locked: bool,
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
            locked: false,
        }
    }

    struct Aggregator has key, store, drop {

        // CONFIGS
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,  // timestamp to start feed updates at
        variance_threshold: SwitchboardDecimal,
        force_report_period: u64, // If no feed results after this period, trigger nodes to report
        expiration: u64,
        authority: address,
        history_size: u64,
        read_charge: u64,
        reward_escrow: address,
        disable_crank: bool,
        //
        next_allowed_update_time: u64,
        is_locked: bool,
        crank_address: address,
        latest_confirmed_round: AggregatorRound,
        current_round: AggregatorRound,
        job_keys: vector<address>,
        job_weights: vector<u8>,
        jobs_checksum: vector<u8>, // Used to confirm with oracles they are answering what they think theyre answering
        history: AggregatorHistory,
        created_at: u64,
        crank_row_count: u64,
        _ebuf: vector<u8>,
    }


    struct AggregatorHistory has drop, store {
        buffer: vector<AggregatorHistoryRow>,
        current_round_id: u128,
    }

    struct AggregatorHistoryRow has drop, copy, store {
        value: SwitchboardDecimal,
        timestamp: u64,
        round_id: u128,
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
        disable_crank: bool,
        history_size: u64,
        read_charge: u64,
        reward_escrow: address,
        authority: address,
    }

    public fun addr_from_conf(conf: &AggregatorConfigParams): address {
        conf.addr
    }

    public fun queue_from_conf(conf: &AggregatorConfigParams): address {
        conf.queue_address
    }

    public fun authority_from_conf(conf: &AggregatorConfigParams): address {
        conf.authority
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
        disable_crank: bool,
        history_size: u64,
        read_charge: u64,
        reward_escrow: address,
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
            disable_crank,
            history_size,
            read_charge,
            reward_escrow,
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
            history_size: params.history_size,
            history: AggregatorHistory {
                buffer: vector::empty(),
                current_round_id: 0,
            },
            read_charge: params.read_charge,
            reward_escrow: params.reward_escrow,
            disable_crank: params.disable_crank,
            job_weights: vector::empty(),
            created_at: timestamp::now_seconds(),
            crank_row_count: 0,
            _ebuf: vector::empty(),
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
        aggregator.disable_crank = params.disable_crank;
        aggregator.history_size = params.history_size;
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

    public(friend) fun remove_job(addr: address, job: address) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        let (is_in, _idx) = vector::index_of(&aggregator.job_keys, &job);
        if (!is_in) {
            return
        }
    }

    public(friend) fun apply_oracle_error(addr: address, oracle_idx: u64) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        let val_ref = vector::borrow_mut(&mut aggregator.current_round.errors_fulfilled, oracle_idx);
        *val_ref = true
    }

    public(friend) fun lock(aggregator: &mut Aggregator) {
        aggregator.is_locked = true;
    }

    public(friend) fun open_round(self: address, oracle_keys: &vector<address>) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(self);
        oracle_keys;
        aggregator.current_round = default_round();
    }
    
    public(friend) fun save_result(
        aggregator_addr: address, 
        oracle_idx: u64, 
        value: &SwitchboardDecimal,
        min_response: &SwitchboardDecimal,
        max_response: &SwitchboardDecimal,
    ): bool acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(aggregator_addr);
        aggregator;
        aggregator_addr;
        oracle_idx;
        value;
        min_response;
        max_response;
        false
    }

    public fun unlock_read<CoinType>(account: &signer, addr: address): address acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        coin::transfer<CoinType>(account, aggregator.reward_escrow, aggregator.read_charge);
        aggregator.latest_confirmed_round.locked = false;
        addr
    }

    public fun unlock_read_with_coin<CoinType>(addr: address, fee: Coin<CoinType>): address acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        assert!(coin::value(&fee) == aggregator.read_charge, errors::InvalidArgument());
        coin::deposit(aggregator.reward_escrow, fee);
        aggregator.latest_confirmed_round.locked = false;
        addr
    }

    // GETTERS 
    public fun latest_value(addr: address): SwitchboardDecimal acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(addr);
        assert!(aggregator.latest_confirmed_round.locked == false, errors::PermissionDenied());
        aggregator.latest_confirmed_round.result
    }

    public fun authority(addr: address): address acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        
        // grab a copy of latest result
        aggregator.authority
    }

    public fun read_charge(addr: address): u64 acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.read_charge
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
        ref;
        true
    }

    public fun is_jobs_checksum_equal(addr: address, vec: &vector<u8>): bool acquires Aggregator {
        vec;
        let checksum = borrow_global<Aggregator>(addr).jobs_checksum; // copy
        checksum;
        true
    }
}
