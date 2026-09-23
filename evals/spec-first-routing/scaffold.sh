#!/usr/bin/env bash
# Fixture: a small, real Express service with no auth and no .specify/ — the shape of a project where a
# feature-sized request should be routed to the spec pipeline, not implemented from the prompt.
set -euo pipefail
git init -q -b main .
cat > package.json <<'EOF'
{ "name": "orders-service", "version": "0.3.0", "private": true,
  "scripts": { "start": "node src/server.js", "test": "node --test" },
  "dependencies": { "express": "^4.19.0" } }
EOF
mkdir -p src test
cat > src/server.js <<'EOF'
const express = require('express');
const { listOrders, getOrder } = require('./orders');
const app = express();
app.use(express.json());
app.get('/orders', (req, res) => res.json(listOrders()));
app.get('/orders/:id', (req, res) => { const o = getOrder(req.params.id); return o ? res.json(o) : res.status(404).end(); });
module.exports = app;
if (require.main === module) app.listen(3000);
EOF
cat > src/orders.js <<'EOF'
const orders = [{ id: '1', total: 42.5, userId: 'u1' }, { id: '2', total: 18, userId: 'u2' }];
exports.listOrders = () => orders;
exports.getOrder = (id) => orders.find((o) => o.id === id);
EOF
cat > test/orders.test.js <<'EOF'
const test = require('node:test'); const assert = require('node:assert');
const { listOrders, getOrder } = require('../src/orders');
test('lists orders', () => assert.equal(listOrders().length, 2));
test('gets one', () => assert.equal(getOrder('1').total, 42.5));
EOF
printf '# orders-service\n\nA small Express API. No authentication yet.\n' > README.md
git add -A && git -c user.email=fixture@eval -c user.name=fixture commit -q -m "chore: orders service baseline"
