# n8n 01 — Your first workflow, step by step

**Goal:** understand the five words everything in n8n is built on (**workflow, node, trigger, item, execution**) by building a tiny workflow and reading its data yourself.

**Time:** 25 minutes. **Cost:** $0. **Before you start:** Lesson 06 done; you can sign in at `https://n8n-<your-ip-with-dashes>.sslip.io`.
Nothing in this lesson touches the terminal, the SAR site or your other workflows.

---

## Part A — The five words

| Word | What it is | In real life |
|---|---|---|
| **Workflow** | One automation: a set of steps drawn on a canvas | A recipe |
| **Node** | One step: read, change, decide, send | One line of the recipe |
| **Trigger** | The first node: *what starts the workflow* (a click, a time, a message) | "When guests arrive…" |
| **Item** | One piece of data moving through the nodes (like one row in a table). Nodes run **once per item** | One plate |
| **Execution** | One run of the workflow, saved with all its data so you can look back | Cooking the recipe once |

And two ways to run:

| | **Test run** (button *Execute workflow*) | **Published** (button *Publish*) |
|---|---|---|
| Who starts it | You, in the editor | The trigger, by itself (a schedule, a webhook…) |
| Used for | Building and checking | Real work, 24/7 |
| This lesson | ✅ | Not needed: a "click" trigger only runs when you click |

## Part B — Build it: one node, one item

1. Open n8n → **Overview** → **Create workflow**.
2. Click the name at the top (*My workflow*) and rename it `n8n 01 — first workflow`.
3. Click **Add first step** (the big **+** in the middle) → search `manually` → choose **Trigger manually**.
   A node called *When clicking 'Execute workflow'* appears. It does one thing: start the workflow when you click.
4. Click the small **+** on the right side of that node → search `edit fields` → choose **Edit Fields (Set)**.
5. In the node:
   - **Mode:** Manual Mapping
   - Click **Add Field** three times and fill in:

     | Name | Type | Value |
     |---|---|---|
     | `customer` | String | `Ahmad` |
     | `sar_amount` | Number | `500` |
     | `city` | String | `Riyadh` |

6. Click **Execute step** (top right of the node window). The right side, **OUTPUT**, now shows your data.
7. Close the node window (**Back to canvas** or Esc). Rename the node: click it once, press **F2**, type `Customer details`.

### Read the output three ways

Open **Customer details** again and switch the OUTPUT view at the top of the panel:

| View | Shows | Use it when |
|---|---|---|
| **Schema** | Field names and types (`customer` *abc*, `sar_amount` *#*) | You want to know *what* fields exist |
| **Table** | One row per item, one column per field | You have many items |
| **JSON** | The raw data: `[ { "customer": "Ahmad", "sar_amount": 500, "city": "Riyadh" } ]` | You want the exact truth |

The JSON view is the important one: `[ ]` is a **list of items**, each `{ }` is **one item**, and inside it are **fields** (`"name": value`). Text has quotes, numbers don't.

✅ **Check:** above the output it says **1 item**.

## Part C — Many items: the node runs once per item

Real data usually comes in lists (10 orders, 50 rows). Let's give the trigger three customers.

1. Open the trigger node (*When clicking 'Execute workflow'*). In its OUTPUT panel click **Set mock data** (or the ✏️ pencil), paste this, and click **Save**:

   ```json
   [
     { "customer": "Ahmad", "sar_amount": 500 },
     { "customer": "Usman", "sar_amount": 1200 },
     { "customer": "Sara",  "sar_amount": 75 }
   ]
   ```

   The trigger now always outputs these 3 items. The 📌 pin icon means **"pinned data"**: n8n reuses it instead of running the node. Handy while building.
2. Open **Customer details** and change it so it *adds* to the data instead of replacing it:
   - Delete the `customer` and `sar_amount` fields (🗑 next to each). Keep `city`.
   - Turn on **Include Other Input Fields** (Input fields to include: **All**).
3. Click **Execute workflow** at the bottom of the canvas.

✅ **Check:** both nodes have a green ✓, the line between them says **3 items**, and the **Table** view of *Customer details* shows three rows, each with `customer`, `sar_amount` and `city = Riyadh`.

You never told n8n to loop: **every node automatically runs once for each item it receives.** This is the single most important idea in n8n.

## Part D — Executions: look back at any run

1. At the top of the editor, click **Executions**. Each test run you did is listed with its time and status.
2. Click the newest one: you see the canvas exactly as it ran, and you can open any node to see the data **at that moment**.
3. Click **Editor** to go back.

When a real (published) workflow fails at 3 a.m., this is where you find out why.

Make sure the workflow is saved: the top bar shows **Saved**. If it shows **Save**, click it (or press **Ctrl+S**).

## Part E — Try it yourself (5 minutes)

1. Add a fourth customer to the mock data (`"customer": "Bilal", "sar_amount": 300`). Run again → **4 items**.
2. In *Customer details*, add a field `currency` (String) `SAR`. Run → every item gets it.
3. Change `sar_amount` of one customer to `"abc"` (with quotes) in the mock data. Look at the **Schema** view: the type changes from *#* to *abc*. Put it back to a number.
4. Unpin the trigger (📌 icon → **Unpin**) and run: the trigger now outputs **1 empty item**, so *Customer details* outputs 1 item with only `city` and `currency`. Pin the data again (**Set mock data**) before you leave.

## Checklist

- [ ] Workflow `n8n 01 — first workflow` saved, 2 nodes, both green after a run
- [ ] I can switch between Schema, Table and JSON and explain what `[ ]` and `{ }` mean
- [ ] With 3 pinned items, *Customer details* outputs 3 items without any loop
- [ ] I found my runs under **Executions**

## Check your understanding

1. What's the difference between a node and a trigger?
2. The trigger outputs 5 items. How many times does the next node run?
3. Why don't we need to **Publish** this workflow?
4. What does the 📌 pin do, and why is it useful while building?
5. In `[ { "a": 1 }, { "a": 2 } ]`, how many items are there, and what is `a`?

<details><summary>Answers</summary>

1. A trigger is the first node and decides **when** the workflow starts; other nodes do the work.
2. Five times, once per item.
3. A "Trigger manually" workflow only runs when you click; publishing is for triggers that start by themselves.
4. It freezes a node's output so n8n reuses it instead of running the node again: same test data every time, no waiting, no repeated API calls.
5. Two items; `a` is a field.

</details>

## If something goes wrong

| Problem | Fix |
|---|---|
| I can't find **Edit Fields** | Search `set`; older n8n calls it *Set* |
| No **Set mock data** link on the trigger | Run the workflow once first, then use the ✏️ pencil in the OUTPUT panel (**Edit output**) |
| *"JSON parameter needs to be valid JSON"* | Every text needs double quotes `" "`, items are separated by commas, no comma after the last one |
| The line says **1 item** after pinning | The pin wasn't saved: open the trigger, check the 📌 is shown, paste and **Save** again |
| Only `city` in the output | **Include Other Input Fields** is off |

## Next

**n8n 02 — Data and expressions:** use `{{ }}` to calculate with your data, e.g. turn `sar_amount` into PKR for each customer, and add today's date with `$now`.
