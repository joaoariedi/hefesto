#!/usr/bin/env bash
# Fixture: a two-sided feature surface — a Django list endpoint and the React table that renders it —
# with the cross-boundary coupling that makes "add pagination" look small and reach far.
set -euo pipefail
git init -q -b main .
mkdir -p api/orders web/src/components
cat > api/orders/views.py <<'EOF'
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import Order
from .serializers import OrderSerializer


class OrderListView(APIView):
    def get(self, request):
        qs = Order.objects.filter(user=request.user).order_by("-created_at")
        return Response(OrderSerializer(qs, many=True).data)   # whole list, every call
EOF
cat > api/orders/serializers.py <<'EOF'
from rest_framework import serializers
from .models import Order


class OrderSerializer(serializers.ModelSerializer):
    class Meta:
        model = Order
        fields = ["id", "total", "status", "created_at"]
EOF
cat > api/orders/models.py <<'EOF'
from django.db import models


class Order(models.Model):
    user = models.ForeignKey("auth.User", on_delete=models.CASCADE)
    total = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=16)
    created_at = models.DateTimeField(auto_now_add=True)
EOF
cat > web/src/api.js <<'EOF'
export async function fetchOrders() {
  const r = await fetch('/orders');
  return r.json();            // expects a bare array
}
EOF
cat > web/src/components/OrdersTable.jsx <<'EOF'
import { useEffect, useState } from 'react';
import { fetchOrders } from '../api';

export default function OrdersTable() {
  const [orders, setOrders] = useState([]);
  useEffect(() => { fetchOrders().then(setOrders); }, []);
  return (
    <table>
      <tbody>{orders.map((o) => <tr key={o.id}><td>{o.id}</td><td>{o.total}</td><td>{o.status}</td></tr>)}</tbody>
    </table>
  );
}
EOF
cat > web/src/components/OrdersTable.test.jsx <<'EOF'
import { render, screen } from '@testing-library/react';
import OrdersTable from './OrdersTable';
jest.mock('../api', () => ({ fetchOrders: () => Promise.resolve([{ id: 1, total: 5, status: 'paid' }]) }));
test('renders rows', async () => { render(<OrdersTable />); expect(await screen.findByText('paid')).toBeInTheDocument(); });
EOF
printf '# shop\n\n`api/` Django REST · `web/` React. The orders page loads every order a user ever placed.\n' > README.md
git add -A && git -c user.email=fixture@eval -c user.name=fixture commit -q -m "feat: orders list endpoint and table"
