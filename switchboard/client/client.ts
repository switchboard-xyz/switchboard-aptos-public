import {
  AptosClient,
  AptosAccount,
  FaucetClient,
  Types,
  HexString,
  TokenClient,
} from "aptos";
import * as sbv2 from "@switchboard-xyz/switchboard-v2";
import fetch from "node-fetch";
const BN = require("bn.js");
import Big from "big.js";

const sleep = (time) => new Promise((res) => setTimeout(res, time, ""));

const NODE_URL =
  process.env.APTOS_NODE_URL ?? "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL =
  process.env.APTOS_FAUCET_URL ?? "https://faucet.devnet.aptoslabs.com";

const PID =
  "2B3C332C6C95D3B717FDF3644A7633E8EFA7B1451193891A504A6A292EDC0039".toLowerCase();

async function load(addr: string, type: string): Promise<any> {
  const res = await fetch(`${NODE_URL}/accounts/${addr}/resource/${type}`, {
    method: "get",
    headers: { "Content-Type": "application/json" },
  });
  console.log(res);
}

async function loadBalance(client, addr: HexString): Promise<string> {
  return (
    (
      await client.getAccountResource(
        addr,
        "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>"
      )
    ).data as any
  ).coin.value;
}

async function sendAptosTx(
  client: AptosClient,
  signer: AptosAccount,
  method: string,
  args: Array<any>
): Promise<string> {
  const payload: Types.TransactionPayload = {
    type: "script_function_payload",
    function: method,
    type_arguments: [],
    arguments: args,
  };
  const txnRequest = await client.generateTransaction(
    signer.address(),
    payload,
    {
      max_gas_amount: "5000",
      gas_unit_price: "1",
      gas_currency_code: "XUS",
    }
  );
  const signedTxn = await client.signTransaction(signer, txnRequest);
  const simulation = await client.simulateTransaction(signer, txnRequest);
  if (simulation.success === false) {
    throw new Error(`TxFailure: ${simulation.vm_status}`);
  }
  const transactionRes = await client.submitTransaction(signedTxn);
  await client.waitForTransaction(transactionRes.hash);
  return transactionRes.hash;
}

export class State {
  constructor(readonly client: AptosClient, readonly address: HexString) {}

  async loadData(): Promise<any> {
    return (
      await this.client.getAccountResource(
        this.address,
        `0x${PID}::Switchboard::State`
      )
    ).data;
  }
}

export class Aggregator {
  constructor(readonly client: AptosClient, readonly address: HexString) {}

  async loadData(): Promise<any> {
    return await this.client.getAccountResources(this.address);
  }

  async loadJobs(): Promise<Array<sbv2.OracleJob>> {
    const data = await this.loadData();
    const jobs = data.job_keys.map((key) => new Job(this.client, key));
    const promises: Array<Promise<sbv2.OracleJob>> = [];
    for (let job of jobs) {
      promises.push(job.loadJob());
    }
    return await Promise.all(promises);
  }
}

export class Job {
  constructor(readonly client: AptosClient, readonly address: HexString) {}

  async loadData(): Promise<any> {
    return (
      await this.client.getAccountResource(this.address, `0x${PID}::Job::Job`)
    ).data;
  }

  async loadJob(): Promise<sbv2.OracleJob> {
    const data = await this.loadData();
    return sbv2.OracleJob.decodeDelimited(
      Buffer.from(data.data.slice(2), "hex")
    );
  }
}

(async () => {
  const client = new AptosClient(NODE_URL);
  // console.log(
  // await client.getAccountResource(
  // "0xa77759be2036acd4dc4aa9d8ef9ae7531dd2e5316d415f76204c95cafb8ef7e5",
  // `${PID}::Switchboard::State`
  // )
  // );
  // return;
  const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
  const state = new AptosAccount();
  const stateAccount = new State(client, state.address());
  await faucetClient.fundAccount(state.address(), 5000);
  await sendAptosTx(client, state, `0x${PID}::SwitchboardInitAction::run`, []);
  console.log(`State account ${state.address().hex()} created`);

  const aggregator = new AptosAccount();
  const queue = new AptosAccount();
  const oracle = new AptosAccount();
  const job = new AptosAccount();
  const authority = new AptosAccount();
  await faucetClient.fundAccount(aggregator.address(), 5000);
  await faucetClient.fundAccount(authority.address(), 5000);
  const tokenClient = new TokenClient(client);
  console.log(await loadBalance(client, authority.address()));
  // await sleep(5000);
  console.log(
    await client.getAccountResource(
      state.address().hex().toString(),
      `0x${PID}::Switchboard::State`
    )
  );
  await faucetClient.fundAccount(queue.address(), 5000);
  await faucetClient.fundAccount(oracle.address(), 5000);
  await faucetClient.fundAccount(job.address(), 5000);
  await faucetClient.fundAccount(authority.address(), 5000);
  await faucetClient.fundAccount(authority.address(), 5000);
  await faucetClient.fundAccount(authority.address(), 5000);
  console.log(await loadBalance(client, authority.address()));
  const queue_sig = await sendAptosTx(
    client,
    queue,
    `0x${PID}::OracleQueueInitAction::run`,
    [
      state.address().hex(), // addr
      Buffer.from("").toString("hex"), // name
      Buffer.from("").toString("hex"), // metadata
      authority.address().hex(), // authority
      "120", // oracle_timeout
      "10000", // reward
      "0", // min_stake
      false, // slashing enabled
      "0", // variance_tolerance_multiplier_value
      0, // variance_tolerance_multiplier_scale
      "0", // feed_probation_period
      "0", // consecutive_feed_failure_limit
      "0", // consecutive_oracle_failure_limit
      true, // unpermissioned_feeds_enabled
      true, // unpermissioned_vrf_enabled
      false, // lock_lease_funding
      authority.address().hex(), // mint
      false, // enable buffer relayers
      "1000", // max_size
    ]
  );
  console.log(`Queue: ${queue.address().hex()}`);
  const agg_sig = await sendAptosTx(
    client,
    aggregator,
    `0x${PID}::AggregatorInitAction::run`,
    [
      state.address().hex(), // addr
      Buffer.from("").toString("hex"), // name
      Buffer.from("").toString("hex"), // metadata
      queue.address().hex(), // queue
      "1", // batch size
      "1", // min oracle results
      "1", // num job results
      "5", // update delay
      "0", // start_after
      "1", // variance_threshold_mantissa
      0, // variance_threshold_scale
      "0", // force report period
      "0", // expiration
      authority.address().hex(), // authority
    ]
  );
  console.log(`Aggregator: ${aggregator.address().hex()}`);
  const oracle_sig = await sendAptosTx(
    client,
    oracle,
    `0x${PID}::OracleInitAction::run`,
    [
      state.address().hex(), // addr
      Buffer.from("").toString("hex"), // name
      Buffer.from("").toString("hex"), // metadata
      authority.address().hex(), // authority
      queue.address().hex(), // queue
    ]
  );
  console.log(`Oracle: ${oracle.address().hex()}`);
  const heartbeat_sig = await sendAptosTx(
    client,
    authority,
    `0x${PID}::OracleHeartbeatAction::run`,
    [
      state.address().hex(), // addr
      oracle.address().hex(), // oracle
    ]
  );
  console.log(`Heartbeat signature: ${heartbeat_sig}`);
  const serializedJob = Buffer.from(
    sbv2.OracleJob.encodeDelimited(
      sbv2.OracleJob.create({
        tasks: [
          {
            httpTask: {
              url: "https://www.binance.us/api/v3/ticker/price?symbol=BTCUSD",
            },
          },
          {
            jsonParseTask: {
              path: "$.price",
            },
          },
        ],
      })
    ).finish()
  );
  const job_sig = await sendAptosTx(
    client,
    job,
    `0x${PID}::JobInitAction::run`,
    [
      state.address().hex(), // addr
      Buffer.from("").toString("hex"), // name
      Buffer.from("").toString("hex"), // metadata
      authority.address().hex(), // authority
      serializedJob.toString("hex"), // data
    ]
  );
  console.log(`Job: ${job.address().hex()}`);
  const addJobSig = await sendAptosTx(
    client,
    authority,
    `0x${PID}::AggregatorAddJobAction::run`,
    [
      state.address().hex(), // addr
      aggregator.address().hex(),
      job.address().hex(),
      1,
    ]
  );
  console.log(`Add job sig: ${addJobSig}`);
  const openRoundSig = await sendAptosTx(
    client,
    authority,
    `0x${PID}::AggregatorOpenRoundAction::run`,
    [
      state.address().hex(), // addr
      aggregator.address().hex(),
    ]
  );
  console.log(`Open round sig: ${openRoundSig}`);
  await faucetClient.fundAccount(authority.address(), 50000);
  console.log(await loadBalance(client, authority.address()));
  const saveResultSig = await sendAptosTx(
    client,
    authority,
    `0x${PID}::AggregatorSaveResultAction::run`,
    [
      state.address().hex(), // addr
      oracle.address().hex(),
      aggregator.address().hex(),
      "0",
      false,
      "100",
      0,
      false,
      Buffer.from("").toString("hex"),
    ]
  );
  console.log(`SaveResult sig: ${saveResultSig}`);
  console.log(await loadBalance(client, authority.address()));
  const aggAccount = new Aggregator(client, aggregator.address());
  // await sleep(5000);
  // const aggregatorTableHandle = (await stateAccount.loadData()).data.aggregators
  // .handle;
  // console.log(await aggAccount.loadData());
  // const openRoundEvent = new AptosEvent(
  // client,
  // state.address(),
  // `0x${PID}::Switchboard::State`,
  // "aggregator_open_round_events"
  // );
  // openRoundEvent.onTrigger((event: any) => {
  // console.log(event);
  // });
  // while (true) {
  // let sig = await sendAptosTx(
  // client,
  // job,
  // `0x${PID}::AggregatorOpenRoundAction::run`,
  // [
  // state.address().hex(), // addr
  // aggregator.address().hex(),
  // ]
  // );
  // console.log(sig);
  // }
})();

class AptosDecimal {
  constructor(
    readonly mantissa: string,
    readonly scale: number,
    readonly neg: boolean
  ) {}

  toBig(): Big {
    let result = new Big(this.mantissa);
    if (this.neg === true) {
      result = result.mul(-1);
    }
    const TEN = new Big(10);
    return result.div(TEN.pow(this.scale));
  }

  static fromBig(val: Big): AptosDecimal {
    const value = val.c.slice();
    let e = val.e;
    while (e > 18) {
      value.pop();
      e -= 1;
    }
    return new AptosDecimal(value.join(""), e, val.s === -1);
  }
}

class AptosEvent {
  constructor(
    readonly client: AptosClient,
    readonly eventHandlerOwner: HexString,
    readonly eventOwnerStruct: string,
    readonly eventHandlerName: string
  ) {}

  async onTrigger(callback: (e: any) => any) {
    // Get the start sequence number in the EVENT STREAM, defaulting to the latest event.
    const [{ sequence_number }] = await this.client.getEventsByEventHandle(
      this.eventHandlerOwner,
      this.eventOwnerStruct,
      this.eventHandlerName,
      { limit: 1 }
    );

    // type for this is string for some reason
    let lastSequenceNumber = sequence_number;

    setInterval(async () => {
      const events = await this.client.getEventsByEventHandle(
        this.eventHandlerOwner,
        this.eventOwnerStruct,
        this.eventHandlerName,
        {
          start: Number(lastSequenceNumber) + 1,
        }
      );
      for (let e of events) {
        // increment sequence number
        lastSequenceNumber = e.sequence_number;

        // fire off the callback for all new events
        await callback(e);
      }
    }, 1000);
  }
}
