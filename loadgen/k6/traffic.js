import http from 'k6/http';

const base = __ENV.BASE_URL || 'http://storefront:8080';

export const options = {
  scenarios: {
    traffic: {
      executor: 'constant-arrival-rate',
      rate: 5,
      timeUnit: '1s',
      duration: '24h',
      preAllocatedVUs: 10,
      maxVUs: 50,
    },
  },
};

// Skewed id distribution: a few popular products get most views.
function pickId() {
  return Math.min(200, 1 + Math.floor(Math.pow(Math.random(), 2.5) * 200));
}

export default function () {
  if (Math.random() < 0.85) {
    http.get(`${base}/api/products/${pickId()}`, { tags: { name: 'product' } });
  } else {
    const body = JSON.stringify({ product_id: pickId(), quantity: 1 });
    http.post(`${base}/api/orders`, body, { headers: { 'Content-Type': 'application/json' }, tags: { name: 'order' } });
  }
}
