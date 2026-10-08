-- 200 fictional books from the fictional publisher "Acme Books". Deterministic, no real titles or people.
INSERT INTO products (id, sku, title, author, price_cents, stock, popularity)
SELECT
    n,
    'ACME-' || lpad(n::text, 4, '0'),
    (ARRAY['The Quiet','A Brief','The Hidden','Notes on the','The Last','Beyond the','The Weight of','Letters from the',
           'An Atlas of','The Long'])[1 + (n % 10)]
      || ' ' ||
    (ARRAY['Harbor','Orchard','Signal','Lantern','Archive','Meridian','Foundry','Garden','Compass','Ledger',
           'Winter','Bridge','Engine','Thread','Tide','Canyon','Mirror','Season','Workshop','Horizon'])[1 + ((n * 7) % 20)],
    (ARRAY['A. Novak','B. Okafor','C. Lindqvist','D. Moreau','E. Tanaka','F. Reyes','G. Haddad','H. Kowalski',
           'I. Brandt','J. Mensah','K. Varga','L. Duarte','M. Sato','N. Ivanova','O. Fitzgerald'])[1 + ((n * 11) % 15)],
    799 + ((n * 137) % 2200),
    20 + ((n * 31) % 480),
    -- skewed popularity: low ids are the bestsellers
    GREATEST(1, 10000 / n)
FROM generate_series(1, 200) AS n;
