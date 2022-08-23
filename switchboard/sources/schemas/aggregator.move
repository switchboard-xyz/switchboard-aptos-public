module Switchboard::Aggregator {
    use AptosFramework::timestamp;
    use Switchboard::Math::{Self, SwitchboardDecimal};
    use std::bcs;
    use std::hash;
    use std::option::{Option};
    use std::signer;
    use std::vector;

    struct AggregatorRound has store, copy, drop {
        // Maintains the `solana_program::clock::Unixtimestamp;` the round was opened at.
        round_open_timestamp: u64,
        // Maintains the current median of all successful round responses.
        result: SwitchboardDecimal,
        // Standard deviation of the accepted results in the round.
        std_deviation: SwitchboardDecimal,
        // Maintains the minimum node response this round.
        min_response: SwitchboardDecimal,
        // Maintains the maximum node response this round.
        max_response: SwitchboardDecimal,
        // lease_key: Pubkey,
        // Pubkeys of the oracles fulfilling this round.
        oracle_keys: vector<address>,
        // oracle_pubkeys_size: u32, IMPLIED BY ORACLE_REQUEST_BATCH_SIZE
        // Represents all successful node responses this round. `NaN` if empty.
        medians: vector<Option<SwitchboardDecimal>>,
        // Current rewards/slashes oracles have received this round.
        current_payout: vector<SwitchboardDecimal>,
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

    struct Aggregator has key, store, drop {
        addr: address,
        name: vector<u8>,
        metadata: vector<u8>,
        queue_address: address,
        // CONFIGS
        batch_size: u64,
        min_oracle_results: u64,
        min_job_results: u64,
        min_update_delay_seconds: u64,
        start_after: u64,              // timestamp to start feed updates at
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
        variance_threshold: SwitchboardDecimal,
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
        variance_threshold: SwitchboardDecimal,
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

    public(friend) fun add_crank_row_count(self: &address) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(*self);
        aggregator.crank_row_count = aggregator.crank_row_count + 1;
    }

    public(friend) fun sub_crank_row_count(self: &address) acquires Aggregator {
        let aggregator = borrow_global_mut<Aggregator>(*self);
        aggregator.crank_row_count = aggregator.crank_row_count - 1;
    }

    public(friend) fun crank_row_count(self: &address): u64 acquires Aggregator {
        borrow_global<Aggregator>(*self).crank_row_count
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
            crank_address: @0x0, // TODO: SET CRANK ADDR
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

    public fun batch_size(self: address): u64 acquires Aggregator {
        borrow_global_mut<Aggregator>(self).batch_size
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
}
