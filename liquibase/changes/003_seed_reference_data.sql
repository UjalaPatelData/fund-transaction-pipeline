--liquibase formatted sql

--changeset ujala:003-reject-codes
INSERT INTO reject_codes VALUES ('E01', 'Account not found or closed');
INSERT INTO reject_codes VALUES ('E02', 'Fund code not found');
INSERT INTO reject_codes VALUES ('E03', 'No NAV price for order date');
INSERT INTO reject_codes VALUES ('E04', 'Invalid amount or below fund minimum');
INSERT INTO reject_codes VALUES ('E05', 'Duplicate order reference');
INSERT INTO reject_codes VALUES ('E06', 'Invalid order type');
INSERT INTO reject_codes VALUES ('E07', 'Sell amount exceeds holdings');

--changeset ujala:003-dealers
INSERT INTO dealers VALUES ('D001', 'Maple Wealth Partners');
INSERT INTO dealers VALUES ('D002', 'Lakeshore Investments');
INSERT INTO dealers VALUES ('D003', 'Northern Trust Advisors');

--changeset ujala:003-funds
INSERT INTO funds VALUES ('CDN100', 'Canadian Equity Fund',      'CAD', 500);
INSERT INTO funds VALUES ('BND200', 'Canadian Bond Fund',        'CAD', 500);
INSERT INTO funds VALUES ('GLB300', 'Global Growth Fund',        'CAD', 1000);
INSERT INTO funds VALUES ('MMK400', 'Money Market Fund',         'CAD', 100);

--changeset ujala:003-accounts
INSERT INTO accounts VALUES ('A1001', 'D001', 'Investor One',   'ACTIVE');
INSERT INTO accounts VALUES ('A1002', 'D001', 'Investor Two',   'ACTIVE');
INSERT INTO accounts VALUES ('A1003', 'D002', 'Investor Three', 'ACTIVE');
INSERT INTO accounts VALUES ('A1004', 'D002', 'Investor Four',  'CLOSED');
INSERT INTO accounts VALUES ('A1005', 'D003', 'Investor Five',  'ACTIVE');
