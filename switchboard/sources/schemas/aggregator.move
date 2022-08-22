module Switchboard::Aggregator {
    use AptosFramework::timestamp;
    use Switchboard::Math::{Self, Num};
    use Std::bcs;
    use Std::hash;
    use Std::option::{Option};
    use Std::signer;
    use Std::vector;


    struct AggregatorRound has key, store, copy, drop {
        // Maintains the `solana_program::clock::Unixtimestamp;` the round was opened at.
        round_open_timestamp: u64,
        // Maintains the current median of all successful round responses.
        result: Num,
        // Standard deviation of the accepted results in the round.
        std_deviation: Num,
        // Maintains the minimum node response this round.
        min_response: Num,
        // Maintains the maximum node response this round.
        max_response: Num,
        // lease_key: Pubkey,
        // Pubkeys of the oracles fulfilling this round.
        oracle_keys: vector<address>,
        // oracle_pubkeys_size: u32, IMPLIED BY ORACLE_REQUEST_BATCH_SIZE
        // Represents all successful node responses this round. `NaN` if empty.
        medians: vector<Option<Num>>,
        // Current rewards/slashes oracles have received this round.
        current_payout: vector<Num>,
        // could do specific error codes
        error_fulfilled: vector<bool>,
    }

    public fun default_round(): AggregatorRound {
        AggregatorRound {
            round_open_timestamp: 0,
            result: Math::zero(),
            std_deviation: Math::zero(),
            min_response: Math::zero(),
            max_response: Math::zero(),
            oracle_keys: vector::empty(),
            medians: vector::empty(),
            current_payout: vector::empty(),
            error_fulfilled: vector::empty(),
        }
    }

    struct Aggregator has key, store, copy, drop {
        addr: address,
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,              
        variance_threshold: Num,
        force_report_period: u64, 
        expiration: u64,
        next_allowed_update_time: u64,
        is_locked: bool,
        crank_address: address,
        latest_confirmed_round: AggregatorRound,
        current_round: AggregatorRound,
        job_keys: vector<address>,
        job_weights: vector<u8>,
        job_hashes: vector<vector<u8>>,
        jobs_checksum: vector<u8>,
        authority: address,
        disable_crank: bool,
        created_at: u64,
    }

    struct AggregatorConfigParams has drop, copy {
        state_addr: address,
        addr: address,
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,
        variance_threshold: Num,
        force_report_period: u64,
        expiration: u64,
        authority: address,
    }

    public fun new_config(
        state_addr: address,
        addr: address,
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,
        variance_threshold: Num,
        force_report_period: u64,
        expiration: u64,
        authority: address,
    ): AggregatorConfigParams {
        AggregatorConfigParams {
            state_addr,
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

    public fun can_open_round(addr: address): bool acquires Aggregator {
        let ref = borrow_global<Aggregator>(addr);
        timestamp::now_seconds() >= ref.next_allowed_update_time
    }

    public(friend) fun exist(addr: address): bool {
        exists<Aggregator>(addr)
    }

    public(friend) fun has_authority(addr: address, account: &signer): bool acquires Aggregator {
        let ref = borrow_global<Aggregator>(addr);
        ref.authority == signer::address_of(account)
    }

    public fun state_addr(conf: &AggregatorConfigParams): &address { &conf.state_addr }

    public(friend) fun aggregator_get(addr: address): Aggregator acquires Aggregator {
        *borrow_global<Aggregator>(addr)
    }


    public(friend) fun aggregator_create(account: &signer, aggregator: Aggregator) {
        move_to(account, aggregator);
    }

    public(friend) fun aggregator_set(aggregator: Aggregator) acquires Aggregator {
        let agg = borrow_global_mut<Aggregator>(aggregator.addr);
        *agg = aggregator;
    }

    public fun new(params: AggregatorConfigParams): Aggregator {
        Aggregator {
            addr: params.addr,
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
            job_hashes: vector::empty(),
            jobs_checksum: vector::empty(),
            authority: params.authority,
            /* history: todo */
            disable_crank: false,
            job_weights: vector::empty(),
            created_at: timestamp::now_seconds(),
        }
    }

    public fun set_config(aggregator: &mut Aggregator, params: AggregatorConfigParams) {
        aggregator.addr = params.addr;
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

    public fun key(aggregator: &Aggregator): vector<u8> {
        let key = b"Aggregator";
        let addr = bcs::to_bytes(&aggregator.addr);
        vector::append(&mut key, addr);
        hash::sha3_256(key)
    }

    public fun addr(self: &Aggregator): address {
        self.addr
    }

    public fun queue_from_conf(conf: &AggregatorConfigParams): address {
        conf.queue_address
    }

    public fun crank_disabled(addr: &address): bool acquires Aggregator {
        borrow_global<Aggregator>(*addr).disable_crank
    }

    public fun queue(addr: &address): address acquires Aggregator {
        borrow_global<Aggregator>(*addr).queue_address
    }

    public fun lock(aggregator: &mut Aggregator) {
        aggregator.is_locked = true;
    }


    // GETTERS 
    public fun get_latest_value(addr: address): Num acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        
        // grab a copy of latest result
        *&aggregator.latest_confirmed_round.result
    }
 
    public fun get_next_allowed_timestamp(aggregator: &Aggregator): u64 {
        aggregator.next_allowed_update_time
    }

    public fun get_crank_disabled(aggregator: &Aggregator): bool {
        aggregator.disable_crank
    }

    public fun get_queue_address(aggregator: &Aggregator): address {
        aggregator.queue_address
    }

    public fun get_min_update_delay(aggregator: &Aggregator): u64 {
        aggregator.min_update_delay_seconds
    }

    public fun get_job_keys(aggregator: &Aggregator): &vector<address> {
        &aggregator.job_keys
    }

    public fun get_current_round_oracle_keys(addr: address): vector<address> acquires Aggregator {
        let aggregator = borrow_global<Aggregator>(addr);
        aggregator.current_round.oracle_keys
    }

    public entry fun new_test(account: &signer, value: u128, dec: u8, sign: bool) {
        let aggregator = Aggregator {
            addr: @0x55,
            name: vector::empty(),
            metadata: vector::empty(),
            queue_address: @0x55,
            batch_size: 3,
            min_oracle_results: 1,
            min_job_results: 1,
            min_update_delay_seconds: 5,
            start_after: 0,
            variance_threshold: Math::num(0, 0, false),
            force_report_period: 0, 
            expiration: 0,
            next_allowed_update_time: 0,
            is_locked: false,
            crank_address: @0x55,
            latest_confirmed_round: AggregatorRound {
                round_open_timestamp: 0,
                result: Math::num(value, dec, sign),
                std_deviation: Math::num(3141592653, 9, false),
                min_response: Math::num(3141592653, 9, false),
                max_response: Math::num(3141592653, 9, false),
                oracle_keys: vector::empty(),
                medians: vector::empty(),
                current_payout: vector::empty(),
                error_fulfilled: vector::empty(),
            },
            current_round: AggregatorRound {
                round_open_timestamp: 0,
                result: Math::zero(),
                std_deviation: Math::zero(),
                min_response: Math::zero(),
                max_response: Math::zero(),
                oracle_keys: vector::empty(),
                medians: vector::empty(),
                current_payout: vector::empty(),
                error_fulfilled: vector::empty(),
            },
            job_keys: vector::empty(),
            job_weights: vector::empty(),
            job_hashes: vector::empty(),
            jobs_checksum: vector::empty(),
            authority: @0x55,
            disable_crank: false,
            created_at: 0,
        };

        move_to<Aggregator>(account, aggregator);
    }

    public entry fun update_value(addr: address, value: u128, dec: u8, neg: bool) acquires Aggregator {
        let ref = borrow_global_mut<Aggregator>(addr);
        ref.latest_confirmed_round.result = Math::num(value, dec, neg);
    }
}
