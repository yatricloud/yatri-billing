-- =============================================================================
-- Invoiso — Demo Seed Data for Client Showcase
-- Tenant: Uimitra (0664eb23-bed4-4929-8023-47ca0aaae7ae)
-- Run with service-role key (bypasses RLS)
-- =============================================================================

DO $$
DECLARE
  _tid uuid := '0664eb23-bed4-4929-8023-47ca0aaae7ae';
BEGIN

-- ===== COMPANY INFO =====
INSERT INTO public.company_info (tenant_id, name, address, phone, email, website, gstin, pan_number, country)
VALUES (
  _tid,
  'Uimitra Technologies Pvt. Ltd.',
  '304, Titan House, Opp. ISRO, Satellite Road, Ahmedabad – 380015, Gujarat, India',
  '+91 98765 43210',
  'billing@uimitra.com',
  'https://uimitra.com',
  '24AABCU9603R1ZX',
  'AABCU9603R',
  'India'
)
ON CONFLICT (tenant_id) DO UPDATE
  SET name=EXCLUDED.name, address=EXCLUDED.address, phone=EXCLUDED.phone,
      email=EXCLUDED.email, website=EXCLUDED.website, gstin=EXCLUDED.gstin,
      pan_number=EXCLUDED.pan_number, country=EXCLUDED.country;

-- ===== SETTINGS =====
INSERT INTO public.settings (tenant_id, key, value) VALUES
  (_tid,'currency_code','INR'),(_tid,'currency_symbol','₹'),
  (_tid,'invoice_prefix','INV'),(_tid,'quotation_prefix','QUO'),
  (_tid,'receipt_prefix','RCP'),(_tid,'template','modern'),
  (_tid,'tax_label','GST'),(_tid,'decimal_places','2'),
  (_tid,'date_format','dd/MM/yyyy')
ON CONFLICT (tenant_id,key) DO UPDATE SET value=EXCLUDED.value;

-- ===== COUNTERS =====
INSERT INTO public.invoice_counters(tenant_id,type,last_value) VALUES
  (_tid,'Invoice',12),(_tid,'Quotation',4),(_tid,'Receipt',9)
ON CONFLICT(tenant_id,type) DO UPDATE SET last_value=GREATEST(invoice_counters.last_value,EXCLUDED.last_value);

-- ===== CUSTOMERS =====
INSERT INTO public.customers(id,tenant_id,name,email,phone,address,gstin,business_name) VALUES
('cust-001',_tid,'Rajesh Mehta','rajesh.mehta@techwave.in','+91 98201 11223','B-12, Prahlad Nagar, Ahmedabad – 380015','24AAACR5055K1Z4','TechWave Solutions Pvt. Ltd.'),
('cust-002',_tid,'Priya Sharma','priya@designhub.co','+91 97253 44556','201, DLF Cyber City, Gurugram – 122002','06AAACL5588P1ZP','DesignHub Creative Studio'),
('cust-003',_tid,'Ankit Patel','ankit.patel@growfast.io','+91 99099 77812','Surat Textile Market, Surat – 395002','24AAHCP2345N1ZQ','GrowFast E-Commerce'),
('cust-004',_tid,'Sneha Kulkarni','sneha@blossomretail.com','+91 90290 33445','FC Road, Pune – 411005','27AABCB1234F1Z3','Blossom Retail Pvt. Ltd.'),
('cust-005',_tid,'Vikram Singh','vikram@constructpro.in','+91 88002 55667','Connaught Place, New Delhi – 110001','07AAACV9876B1ZL','ConstructPro Infra'),
('cust-006',_tid,'Meena Joshi','meena.joshi@freshgreens.co','+91 94261 78934','APMC Market, Vashi, Navi Mumbai – 400703','27AABCF5678G1ZR','Fresh Greens Foods'),
('cust-007',_tid,'Arjun Nair','arjun@cloudspark.io','+91 91234 56789','Infopark, Kakkanad, Kochi – 682030','32AADCN2233R1ZT','CloudSpark IT Services'),
('cust-008',_tid,'Deepika Reddy','deepika@medcareplus.com','+91 95500 11223','Banjara Hills, Hyderabad – 500034','36AAACS4567J1Z2','MedCare Plus Hospitals'),
('cust-009',_tid,'Suresh Iyer','suresh.iyer@logixhub.co','+91 98765 00112','Perungudi, Chennai – 600096','33AABCI7890K1ZV','LogixHub Supply Chain'),
('cust-010',_tid,'Kavita Agarwal','kavita@edunest.in','+91 87654 32109','Sector 18, Noida – 201301','09AAACE6543M1ZH','EduNest Learning Solutions')
ON CONFLICT(id) DO NOTHING;

-- ===== PRODUCTS =====
INSERT INTO public.products(id,tenant_id,name,description,price,stock,hsncode,tax_rate,type,default_discount,purchase_price,unit,unlimited_stock,price_includes_tax) VALUES
('prod-001',_tid,'UI/UX Design Package','Complete end-to-end design for web & mobile apps',45000,NULL,'998314',18,'service',5,0,'pkg',1,0),
('prod-002',_tid,'Web Development – Basic','Static website up to 5 pages with responsive design',25000,NULL,'998313',18,'service',0,0,'pkg',1,0),
('prod-003',_tid,'Web Development – Pro','Dynamic website with CMS and up to 20 pages',75000,NULL,'998313',18,'service',10,0,'pkg',1,0),
('prod-004',_tid,'SEO Optimisation – Monthly','On-page & off-page SEO, monthly reporting',12000,NULL,'998361',18,'service',0,0,'month',1,0),
('prod-005',_tid,'Social Media Management','Content calendar, posting & analytics – 30 days',8500,NULL,'998369',18,'service',0,0,'month',1,0),
('prod-006',_tid,'Brand Identity Kit','Logo, brand guidelines, business card & letterhead',18000,NULL,'998314',18,'service',5,0,'kit',1,0),
('prod-007',_tid,'Annual Maintenance Contract','Hosting + updates + support for 12 months',36000,NULL,'998315',18,'service',0,0,'yr',1,0),
('prod-008',_tid,'Mobile App Development','Cross-platform Flutter app (iOS & Android)',120000,NULL,'998313',18,'service',0,0,'app',1,0),
('prod-009',_tid,'Photography – Product Shoot','Professional product photography (50 images)',9500,NULL,'999800',18,'service',5,0,'shoot',1,0),
('prod-010',_tid,'Digital Marketing Campaign','Google & Meta Ads management for 30 days',15000,NULL,'998366',18,'service',0,0,'month',1,0),
('prod-011',_tid,'Laptop – Dell Inspiron 15','Intel i5 12th gen, 16GB RAM, 512GB SSD',62990,8,'847130',18,'product',5,52000,'pcs',0,0),
('prod-012',_tid,'Wireless Mouse – Logitech','Ergonomic, 2.4GHz, 1-year battery life',1299,45,'847160',18,'product',0,850,'pcs',0,0)
ON CONFLICT(id) DO NOTHING;

-- ===== INVOICES =====
INSERT INTO public.invoices(id,tenant_id,customer_id,customer_name,customer_email,customer_phone,customer_address,customer_gstin,customer_business_name,date,notes,tax_rate,type,currency_code,currency_symbol,tax_mode,due_date,invoice_number,invoice_title) VALUES
('inv-001',_tid,'cust-001','Rajesh Mehta','rajesh.mehta@techwave.in','+91 98201 11223','B-12, Prahlad Nagar, Ahmedabad','24AAACR5055K1Z4','TechWave Solutions Pvt. Ltd.','2026-08-05T00:00:00','First milestone – UI/UX design project.',18,'Invoice','INR','₹','perItem','2026-08-20T00:00:00','INV-001','Tax Invoice'),
('inv-002',_tid,'cust-002','Priya Sharma','priya@designhub.co','+91 97253 44556','201, DLF Cyber City, Gurugram','06AAACL5588P1ZP','DesignHub Creative Studio','2026-08-12T00:00:00','Brand Identity Kit + Social Media onboarding.',18,'Invoice','INR','₹','perItem','2026-08-27T00:00:00','INV-002','Tax Invoice'),
('inv-003',_tid,'cust-003','Ankit Patel','ankit.patel@growfast.io','+91 99099 77812','Surat Textile Market, Surat','24AAHCP2345N1ZQ','GrowFast E-Commerce','2026-08-18T00:00:00','E-commerce website Pro package.',18,'Invoice','INR','₹','perItem','2026-09-02T00:00:00','INV-003','Tax Invoice'),
('inv-004',_tid,'cust-004','Sneha Kulkarni','sneha@blossomretail.com','+91 90290 33445','FC Road, Pune','27AABCB1234F1Z3','Blossom Retail Pvt. Ltd.','2026-08-25T00:00:00','Monthly SEO + Social Media retainer.',18,'Invoice','INR','₹','perItem','2026-09-09T00:00:00','INV-004','Tax Invoice'),
('inv-005',_tid,'cust-005','Vikram Singh','vikram@constructpro.in','+91 88002 55667','Connaught Place, New Delhi','07AAACV9876B1ZL','ConstructPro Infra','2026-09-01T00:00:00','Mobile App Development – advance 50%.',18,'Invoice','INR','₹','perItem','2026-09-16T00:00:00','INV-005','Tax Invoice'),
('inv-006',_tid,'cust-006','Meena Joshi','meena.joshi@freshgreens.co','+91 94261 78934','APMC Market, Vashi, Mumbai','27AABCF5678G1ZR','Fresh Greens Foods','2026-08-10T00:00:00','Photography shoot + Digital Campaign.',18,'Invoice','INR','₹','perItem','2026-08-25T00:00:00','INV-006','Tax Invoice'),
('inv-007',_tid,'cust-007','Arjun Nair','arjun@cloudspark.io','+91 91234 56789','Infopark, Kochi','32AADCN2233R1ZT','CloudSpark IT Services','2026-09-03T00:00:00','Quotation for AMC + web dev pro upgrade.',18,'Quotation','INR','₹','perItem','2026-09-18T00:00:00','QUO-001','Quotation'),
('inv-008',_tid,'cust-008','Deepika Reddy','deepika@medcareplus.com','+91 95500 11223','Banjara Hills, Hyderabad','36AAACS4567J1Z2','MedCare Plus Hospitals','2026-09-05T00:00:00','Hardware supply – Dell laptops x2, Mice x10.',18,'Invoice','INR','₹','perItem','2026-09-20T00:00:00','INV-008','Tax Invoice'),
('inv-009',_tid,'cust-009','Suresh Iyer','suresh.iyer@logixhub.co','+91 98765 00112','Perungudi, Chennai','33AABCI7890K1ZV','LogixHub Supply Chain','2026-09-08T00:00:00','Digital Marketing Campaign – September.',18,'Invoice','INR','₹','perItem','2026-09-23T00:00:00','INV-009','Tax Invoice'),
('inv-010',_tid,'cust-010','Kavita Agarwal','kavita@edunest.in','+91 87654 32109','Sector 18, Noida','09AAACE6543M1ZH','EduNest Learning Solutions','2026-09-10T00:00:00','E-learning portal – Web Dev Basic.',18,'Invoice','INR','₹','perItem','2026-09-25T00:00:00','INV-010','Tax Invoice'),
('inv-011',_tid,'cust-001','Rajesh Mehta','rajesh.mehta@techwave.in','+91 98201 11223','B-12, Prahlad Nagar, Ahmedabad','24AAACR5055K1Z4','TechWave Solutions Pvt. Ltd.','2026-09-12T00:00:00','Second milestone – UI/UX design delivery.',18,'Invoice','INR','₹','perItem','2026-09-27T00:00:00','INV-011','Tax Invoice'),
('inv-012',_tid,'cust-003','Ankit Patel','ankit.patel@growfast.io','+91 99099 77812','Surat Textile Market, Surat','24AAHCP2345N1ZQ','GrowFast E-Commerce','2026-09-15T00:00:00','SEO Optimisation – September retainer.',18,'Invoice','INR','₹','perItem','2026-09-30T00:00:00','INV-012','Tax Invoice')
ON CONFLICT(id) DO NOTHING;

-- ===== INVOICE ITEMS =====
INSERT INTO public.invoice_items(id,tenant_id,invoice_id,product_id,product_name,product_description,product_price,product_tax_rate,product_hsn_code,quantity,discount,unit_price,extra_cost,product_type,product_unit) VALUES
('ii-001-1',_tid,'inv-001','prod-001','UI/UX Design Package','Complete design',45000,18,'998314',1,5,45000,0,'service','pkg'),
('ii-001-2',_tid,'inv-001','prod-004','SEO Optimisation – Monthly','On-page SEO',12000,18,'998361',1,0,12000,0,'service','month'),
('ii-002-1',_tid,'inv-002','prod-006','Brand Identity Kit','Logo, brand guidelines',18000,18,'998314',1,5,18000,0,'service','kit'),
('ii-002-2',_tid,'inv-002','prod-005','Social Media Management','Content & analytics',8500,18,'998369',1,0,8500,0,'service','month'),
('ii-003-1',_tid,'inv-003','prod-003','Web Development – Pro','Dynamic CMS website',75000,18,'998313',1,10,75000,0,'service','pkg'),
('ii-004-1',_tid,'inv-004','prod-004','SEO Optimisation – Monthly','On-page SEO',12000,18,'998361',1,0,12000,0,'service','month'),
('ii-004-2',_tid,'inv-004','prod-005','Social Media Management','30-day content plan',8500,18,'998369',1,0,8500,0,'service','month'),
('ii-005-1',_tid,'inv-005','prod-008','Mobile App Development','Flutter cross-platform app',120000,18,'998313',0.5,0,120000,0,'service','app'),
('ii-006-1',_tid,'inv-006','prod-009','Photography – Product Shoot','50 product images',9500,18,'999800',1,5,9500,0,'service','shoot'),
('ii-006-2',_tid,'inv-006','prod-010','Digital Marketing Campaign','Google & Meta Ads',15000,18,'998366',1,0,15000,0,'service','month'),
('ii-007-1',_tid,'inv-007','prod-007','Annual Maintenance Contract','12-month support',36000,18,'998315',1,0,36000,0,'service','yr'),
('ii-007-2',_tid,'inv-007','prod-003','Web Development – Pro','CMS upgrade',75000,18,'998313',1,10,75000,0,'service','pkg'),
('ii-008-1',_tid,'inv-008','prod-011','Laptop – Dell Inspiron 15','i5 12th, 16GB, 512SSD',62990,18,'847130',2,5,62990,0,'product','pcs'),
('ii-008-2',_tid,'inv-008','prod-012','Wireless Mouse – Logitech','Ergonomic 2.4GHz',1299,18,'847160',10,0,1299,0,'product','pcs'),
('ii-009-1',_tid,'inv-009','prod-010','Digital Marketing Campaign','Sep Google & Meta Ads',15000,18,'998366',1,0,15000,0,'service','month'),
('ii-010-1',_tid,'inv-010','prod-002','Web Development – Basic','Static 5-page website',25000,18,'998313',1,0,25000,0,'service','pkg'),
('ii-011-1',_tid,'inv-011','prod-001','UI/UX Design Package','Milestone 2 delivery',45000,18,'998314',1,5,45000,0,'service','pkg'),
('ii-012-1',_tid,'inv-012','prod-004','SEO Optimisation – Monthly','Sep on-page SEO',12000,18,'998361',1,0,12000,0,'service','month')
ON CONFLICT(id) DO NOTHING;

-- ===== PAYMENTS =====
INSERT INTO public.invoice_payments(id,tenant_id,invoice_id,invoice_number,receipt_number,amount_paid,tax_amount_paid,previously_paid,balance_after,date_paid,payment_method,notes) VALUES
('pay-001',_tid,'inv-001','INV-001','RCP-001',64575,9855,0,0,'2026-08-20T10:30:00','UPI','Full payment via GPay'),
('pay-002',_tid,'inv-002','INV-002','RCP-002',15000,2288,0,15208,'2026-08-27T14:00:00','Bank Transfer','Advance 50% against brand kit'),
('pay-003',_tid,'inv-003','INV-003','RCP-003',79650,12150,0,0,'2026-09-02T11:00:00','Bank Transfer','Full payment – web project'),
('pay-005',_tid,'inv-005','INV-005','RCP-005',70800,10800,0,0,'2026-09-16T09:00:00','Cheque','Advance cheque #CHQ20260916'),
('pay-008',_tid,'inv-008','INV-008','RCP-008',156552,23882,0,0,'2026-09-06T16:30:00','Bank Transfer','NEFT – hardware supply'),
('pay-009',_tid,'inv-009','INV-009','RCP-009',10000,1525,0,7700,'2026-09-15T12:00:00','UPI','Partial advance Sep campaign'),
('pay-011',_tid,'inv-011','INV-011','RCP-011',50445,7695,0,0,'2026-09-13T10:00:00','UPI','Milestone 2 payment via PhonePe'),
('pay-012',_tid,'inv-012','INV-012','RCP-012',14160,2160,0,0,'2026-09-16T15:00:00','UPI','Monthly retainer – SEO')
ON CONFLICT(id) DO NOTHING;

END $$;
