-- =====================================================================
-- miyshop E-Ticaret Veritabani Sistemi - Tam Kurulum Betigi
-- Grup: 241307022 Mustafa Yigit Genc -- 241307056 Ibrahim Akkus
-- Ders: TBL331 Veritabani Yonetim Sistemleri (2025-2026 Bahar)
-- KULLANIM: Once alttaki DROP komutlarini calistirin, sonra bu betigi bastan sona calistirin.
-- DROP: USE master; ALTER DATABASE ETicaretDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ETicaretDB;
-- =====================================================================

CREATE DATABASE ETicaretDB;
GO
USE ETicaretDB;
GO

-- =====================================================================
-- BOLUM 1: TABLOLAR (8 ADET)
-- =====================================================================

CREATE TABLE Kategori (
    KategoriID  INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE Musteri (
    MusteriID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad           NVARCHAR(50)  NOT NULL,
    Soyad        NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(100) NOT NULL UNIQUE,
    KayitTarihi  DATE NOT NULL DEFAULT GETDATE()
);

CREATE TABLE Magaza (
    MagazaID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(100) NOT NULL UNIQUE,
    Sehir       NVARCHAR(50)  NOT NULL,
    Puan        DECIMAL(2,1)  NOT NULL DEFAULT 0 CHECK (Puan >= 0 AND Puan <= 5),
    KayitTarihi DATE NOT NULL DEFAULT GETDATE()
);

CREATE TABLE Urun (
    UrunID      INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(120) NOT NULL,
    Fiyat       DECIMAL(10,2) NOT NULL CHECK (Fiyat > 0),
    StokAdedi   INT NOT NULL DEFAULT 0 CHECK (StokAdedi >= 0),
    KategoriID  INT NOT NULL,
    MagazaID    INT NOT NULL,
    GorselURL   NVARCHAR(500),
    CONSTRAINT FK_Urun_Kategori FOREIGN KEY (KategoriID) REFERENCES Kategori(KategoriID),
    CONSTRAINT FK_Urun_Magaza   FOREIGN KEY (MagazaID)   REFERENCES Magaza(MagazaID)
);

-- Urun beden/renk/tur varyantlari ve varyanta ozel stok
CREATE TABLE UrunVaryant (
    VaryantID   INT IDENTITY(1,1) PRIMARY KEY,
    UrunID      INT NOT NULL,
    Beden       NVARCHAR(20),
    Renk        NVARCHAR(30),
    Stok        INT NOT NULL DEFAULT 0 CHECK (Stok >= 0),
    CONSTRAINT FK_Varyant_Urun FOREIGN KEY (UrunID) REFERENCES Urun(UrunID),
    CONSTRAINT CK_Varyant_BedenveyaRenk CHECK (Beden IS NOT NULL OR Renk IS NOT NULL)
);

CREATE TABLE Siparis (
    SiparisID     INT IDENTITY(1,1) PRIMARY KEY,
    MusteriID     INT NOT NULL,
    SiparisTarihi DATETIME NOT NULL DEFAULT GETDATE(),
    Durum         NVARCHAR(20) NOT NULL DEFAULT 'Hazirlaniyor'
                  CHECK (Durum IN ('Hazirlaniyor','Kargoda','Teslim','Iptal')),
    CONSTRAINT FK_Siparis_Musteri FOREIGN KEY (MusteriID) REFERENCES Musteri(MusteriID)
);

-- Siparis-Urun N:N iliskisini cozen ara tablo
-- BirimFiyat: siparis anindaki fiyati saklar
CREATE TABLE SiparisDetay (
    DetayID     INT IDENTITY(1,1) PRIMARY KEY,
    SiparisID   INT NOT NULL,
    UrunID      INT NOT NULL,
    Adet        INT NOT NULL CHECK (Adet > 0),
    BirimFiyat  DECIMAL(10,2) NOT NULL CHECK (BirimFiyat > 0),
    VaryantID   INT NULL,
    CONSTRAINT FK_Detay_Siparis FOREIGN KEY (SiparisID) REFERENCES Siparis(SiparisID),
    CONSTRAINT FK_Detay_Urun    FOREIGN KEY (UrunID)    REFERENCES Urun(UrunID),
    CONSTRAINT FK_Detay_Varyant FOREIGN KEY (VaryantID) REFERENCES UrunVaryant(VaryantID)
);

CREATE TABLE Yorum (
    YorumID   INT IDENTITY(1,1) PRIMARY KEY,
    UrunID    INT NOT NULL,
    MusteriID INT NOT NULL,
    Puan      INT NOT NULL CHECK (Puan BETWEEN 1 AND 5),
    Metin     NVARCHAR(300),
    Tarih     DATE NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Yorum_Urun    FOREIGN KEY (UrunID)    REFERENCES Urun(UrunID),
    CONSTRAINT FK_Yorum_Musteri FOREIGN KEY (MusteriID) REFERENCES Musteri(MusteriID)
);
GO

-- =====================================================================
-- BOLUM 2: INDEXLER (6 ADET)
-- =====================================================================
CREATE INDEX IX_Urun_Kategori   ON Urun(KategoriID);
CREATE INDEX IX_Urun_Magaza     ON Urun(MagazaID);
CREATE INDEX IX_Siparis_Musteri ON Siparis(MusteriID);
CREATE INDEX IX_Detay_Siparis   ON SiparisDetay(SiparisID);
CREATE INDEX IX_Yorum_Urun      ON Yorum(UrunID);
CREATE INDEX IX_Yorum_Musteri   ON Yorum(MusteriID);
GO

-- =====================================================================
-- BOLUM 3: TRIGGER'LAR (2 ADET)
-- =====================================================================

-- Siparis verilince hem urun hem varyant stogu duser
CREATE TRIGGER trg_StokDus
ON SiparisDetay
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE u SET u.StokAdedi = u.StokAdedi - i.Adet
    FROM Urun u INNER JOIN inserted i ON u.UrunID = i.UrunID;

    UPDATE v SET v.Stok = v.Stok - i.Adet
    FROM UrunVaryant v INNER JOIN inserted i ON v.VaryantID = i.VaryantID
    WHERE i.VaryantID IS NOT NULL;
END;
GO

-- Siparis iptal edilince stok geri gelir
CREATE TRIGGER trg_IptalStokGeri
ON Siparis
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE u SET u.StokAdedi = u.StokAdedi + sd.Adet
    FROM Urun u
    JOIN SiparisDetay sd ON u.UrunID     = sd.UrunID
    JOIN inserted i      ON sd.SiparisID = i.SiparisID
    JOIN deleted  d      ON d.SiparisID  = i.SiparisID
    WHERE i.Durum = 'Iptal' AND d.Durum <> 'Iptal';

    UPDATE v SET v.Stok = v.Stok + sd.Adet
    FROM UrunVaryant v
    JOIN SiparisDetay sd ON v.VaryantID = sd.VaryantID
    JOIN inserted i      ON sd.SiparisID = i.SiparisID
    JOIN deleted  d      ON d.SiparisID  = i.SiparisID
    WHERE i.Durum = 'Iptal' AND d.Durum <> 'Iptal'
      AND sd.VaryantID IS NOT NULL;
END;
GO

-- =====================================================================
-- BOLUM 4: STORED PROCEDURE'LAR (3 ADET)
-- =====================================================================

CREATE PROCEDURE sp_SepetToplami
    @SiparisID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SUM(Adet * BirimFiyat) AS ToplamTutar
    FROM SiparisDetay WHERE SiparisID = @SiparisID;
END;
GO

CREATE PROCEDURE sp_MusteriOzet
    @MusteriID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SiparisID, s.SiparisTarihi,
           SUM(sd.Adet * sd.BirimFiyat) AS SiparisTutari
    FROM Siparis s
    JOIN SiparisDetay sd ON s.SiparisID = sd.SiparisID
    WHERE s.MusteriID = @MusteriID
    GROUP BY s.SiparisID, s.SiparisTarihi;
END;
GO

CREATE PROCEDURE sp_SatisRaporu
AS
BEGIN
    SET NOCOUNT ON;
    SELECT k.Ad AS Kategori,
           COUNT(DISTINCT sd.SiparisID) AS SiparisSayisi,
           SUM(sd.Adet)                 AS ToplamAdet,
           SUM(sd.Adet * sd.BirimFiyat) AS ToplamCiro
    FROM SiparisDetay sd
    JOIN Urun u     ON sd.UrunID    = u.UrunID
    JOIN Kategori k ON u.KategoriID = k.KategoriID
    GROUP BY k.Ad ORDER BY ToplamCiro DESC;
END;
GO

-- =====================================================================
-- BOLUM 5: VIEW'LAR (3 ADET)
-- =====================================================================

CREATE VIEW vw_SiparisOzeti AS
SELECT s.SiparisID, m.Ad+' '+m.Soyad AS Musteri, s.SiparisTarihi,
       u.Ad AS Urun, sd.Adet, sd.BirimFiyat, (sd.Adet*sd.BirimFiyat) AS SatirTutar
FROM Siparis s
JOIN Musteri m       ON s.MusteriID  = m.MusteriID
JOIN SiparisDetay sd ON s.SiparisID  = sd.SiparisID
JOIN Urun u          ON sd.UrunID    = u.UrunID;
GO

CREATE VIEW vw_KritikStok AS
SELECT u.UrunID, u.Ad, u.StokAdedi, k.Ad AS Kategori
FROM Urun u JOIN Kategori k ON u.KategoriID = k.KategoriID
WHERE u.StokAdedi < 10;
GO

CREATE VIEW vw_SatisDetaylari AS
SELECT s.SiparisID, s.SiparisTarihi, s.Durum,
       m.Ad+' '+m.Soyad AS Musteri, u.Ad AS Urun,
       k.Ad AS Kategori, mg.Ad AS Magaza,
       sd.Adet, sd.BirimFiyat, (sd.Adet*sd.BirimFiyat) AS SatirTutar
FROM Siparis s
JOIN Musteri m       ON s.MusteriID  = m.MusteriID
JOIN SiparisDetay sd ON s.SiparisID  = sd.SiparisID
JOIN Urun u          ON sd.UrunID    = u.UrunID
JOIN Kategori k      ON u.KategoriID = k.KategoriID
JOIN Magaza mg       ON u.MagazaID   = mg.MagazaID;
GO

-- =====================================================================
-- BOLUM 6: TEST VERILERI
-- =====================================================================

INSERT INTO Kategori (Ad) VALUES
(N'Giyim & Moda'),(N'Oto Aksesuar'),(N'Elektronik'),
(N'Oyun & Hobi'),(N'Ev & Yaşam'),(N'Spor & Outdoor'),
(N'Telefon & Tablet'),(N'Kitap & Kırtasiye'),
(N'Bahçe & Yapı Market'),(N'Mutfak & Gıda');

INSERT INTO Musteri (Ad, Soyad, Email) VALUES
(N'İbrahim',N'Akkuş','ibrahim.akkus@mail.com'),
(N'Buket',N'Yılmaz','buket.yilmaz@mail.com'),
(N'Sude',N'Demir','sude.demir@mail.com'),
(N'Furkan',N'Kaya','furkan.kaya@mail.com'),
(N'Elif',N'Şahin','elif.sahin@mail.com'),
(N'Mert',N'Aydın','mert.aydin@mail.com'),
(N'Zeynep',N'Çelik','zeynep.celik@mail.com'),
(N'Emre',N'Doğan','emre.dogan@mail.com'),
(N'Merve',N'Arslan','merve.arslan@mail.com'),
(N'Kerem',N'Öztürk','kerem.ozturk@mail.com');

INSERT INTO Magaza (Ad, Sehir, Puan) VALUES
(N'SportZone',N'İstanbul',4.5),
(N'OtoPlus',N'Kocaeli',4.2),
(N'TechNova',N'Ankara',4.8),
(N'HobiDünyam',N'İzmir',4.0),
(N'HomeStyle',N'Bursa',3.9),
(N'OutdoorFlex',N'Antalya',4.6),
(N'MobilPro',N'İstanbul',4.1),
(N'KitapEvim',N'Eskişehir',4.7),
(N'BahçeExpress',N'Konya',3.8),
(N'MutfakDepo',N'Adana',4.3);

INSERT INTO Urun (Ad, Fiyat, StokAdedi, KategoriID, MagazaID, GorselURL) VALUES
(N'Fenerbahçe x adidas 2025-26 120. Yıl Özel Forma',1999.90,50,1,1,'https://media.fenerium.com/Fenerium/media/images/urunler/AT013EGP02500.jpg'),
(N'Galatasaray UCL Şampiyonlar Ligi Özel Baskı Forma',2199.90,40,1,1,'https://pbs.twimg.com/media/F9NrKqQbUAAQlEw?format=jpg&name=900x900'),
(N'Renault Clio Uyumlu Havuzlu Paspas',399.00,30,2,2,'https://productimages.hepsiburada.net/s/38/375-375/10615221125170.jpg'),
(N'Fiat Linea Sis Farı (Sağ)',279.90,7,2,2,'https://asrotomotiv.com.tr/cdn/shop/files/GUA41835_1_Takim_3c67fa81-6c0f-4cf2-bcbd-543186cf253b.jpg?v=1748259776&width=1946'),
(N'Redragon K552 Kumara Mekanik Oyuncu Klavyesi',799.00,15,3,3,'https://www.incehesap.com/resim/urun/202112/61bcb8953c5cd0.79734065_hemkjniqgflpo_500.webp'),
(N'Logitech G304 Kablosuz Oyuncu Mouse',649.00,60,3,3,'https://cdn.akakce.com/_static/1193014634/logitech-g304.png'),
(N'101 Plus Okey Seti',299.00,35,4,4,'https://cdn.akakce.com/z/star/star-101-plus-plastik.jpg'),
(N'Ahşap Satranç Takımı',249.00,8,4,4,'https://www.banabirhediye.com/cdn/shop/files/BuyukIMG_4901.webp?v=1749608492&width=1445'),
(N'4 Kişilik Pamuklu Nevresim Takımı',799.00,18,5,5,'https://dafnemoda.com/wp-content/uploads/2025/11/image_1950-205-scaled.webp'),
(N'Paslanmaz Çelik Çaydanlık',449.90,22,10,10,'https://www.tantitoni.com.tr/orta-boy-paslanmaz-celik-caydanlik-takimi-9801700ml-caydanliklar-ve-cezveler-tantitoni-12429-15-B.jpg'),
(N'JBL Tune 510BT Kablosuz Kulak Üstü Kulaklık',899.00,45,6,6,'https://cdn.vatanbilgisayar.com/Upload/PRODUCT/jbl/thumb/128898-4_large.jpg'),
(N'Spigen Ultra Hybrid iPhone 15 Şeffaf Kılıf',249.90,80,7,7,'https://www.spigen.com.tr/shop/bu/08/myassets/products/865/acs06793-6_min.jpg?revision=1756301237'),
(N'Pegem KPSS 2026 Genel Kültür Soru Bankası',219.00,55,8,8,'https://pegem.net/uploads/p/p/2026-KPSS-On-Lisans-Genel-Yetenek-Genel-Kultur-Tamami-Video-Cozumlu-E-Soru-Bankasi_1.jpg'),
(N'Bahçe Sulama Hortumu 30m',349.00,20,9,9,'https://cdn.dsmcdn.com/ty1687/prod/QC_PREP/20250530/18/78e2d989-373e-351e-bff6-424174e2edcc/1_org_zoom.jpg'),
(N'Takım Elbise Kıyafet Koruyucu',99.90,100,1,1,'https://productimages.hepsiburada.net/s/161/375-375/110000119408351.jpg'),
(N'Beşiktaş 2025-26 İç Saha Siyah-Beyaz Forma',1799.90,35,1,1,'https://esvaphane.com/wp-content/uploads/2025/06/5853091_CAM_Onsite_TR_Aclubs_BJK_PLP_FW_25_PLP_Desktop_1440x1080px_Home_97b7b3ed68as.jpg'),
(N'Audi A3 Uyumlu Ön Panjur Çerçevesi',649.00,12,2,2,'https://cdn.dsmcdn.com/ty1859/prod/QC_ENRICHMENT/20260422/11/866dcb65-1499-3a2d-b1ce-26112ee7279a/1_org_zoom.jpg'),
(N'MSI G274QPF 27" QHD 165Hz IPS Oyuncu Monitörü',8999.00,8,3,3,'https://storage-asset.msi.com/global/picture/image/feature/monitor/G274QPF-E2/kv-mnt.png'),
(N'Monopoly Türkiye Baskısı',449.90,5,4,4,'https://cdn.dsmcdn.com/ty275/product/media/images/20211220/10/13700327/61125091/1/1_org_zoom.jpg'),
(N'Boyun Yastığı Memory Foam',499.00,25,5,5,'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQZ78QuYAAbdTFlh44mwx4zUPKvnQiD51oJug&s'),
(N'Adidas Superstar OG Beyaz Unisex Sneaker',3499.00,20,6,6,'https://aad216.a-cdn.akinoncloud.com/products/2023/09/27/84453/fb32c2f9-1440-4b95-8f21-f0aa98ff8382_size2010x2010_cropCenter.jpg'),
(N'Samsung 25W USB-C Hızlı Şarj Aleti',449.00,70,7,7,'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT3CCdslb9WtYlPSw19QRmFRBBBWxQCVhamIw&s'),
(N'Türkçe-İngilizce Büyük Sözlük',199.00,40,8,8,'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS-AW4UaNmMiyKR58q6cq5hLCXteSB7yboDHg&s'),
(N'Ceviz Ağacı Özel Gübre 1 kg',89.90,30,9,9,'https://cdn.dsmcdn.com/mnresize/420/620/ty1355/product/media/images/prod/QC/20240609/20/6cafb193-ef7d-330e-9c3b-15c78a31b902/1_org_zoom.jpg'),
(N'Tefal SW342 Çift Taraflı Waffle Makinesi 1200W',999.00,15,10,10,'https://www.tefal.com/medias/?context=bWFzdGVyfGltYWdlc3wxMzUyN3xpbWFnZS9qcGVnfGFXMWhaMlZ6TDJnME1TOW9ObVF2TWprek1UWTRNelV6TkRRME1UUXxlMTI1ODA1M2RjMWM4OTQ2MTQ4ZDE1OWQ5ZjJmOWZjOGJhMWRmNTg5MDNhMWVlNzQ5ZmE3NGZiYTg4MGQwOGM4'),
(N'Converse Chuck Taylor All Star Hi Top Siyah',2999.00,18,1,1,'https://akn-converse.a-cdn.akinoncloud.com/products/2025/05/13/81429/c243158d-d3a3-495c-893f-91ef278282ac_size1340x1000_cropBottom.jpg'),
(N'Seiko Presage SRPH89 Otomatik Kol Saati',15999.00,10,5,5,'https://www.abtsaat.com/productimages/101214/big/seiko-srph89k-conceptual-erkek-kol-saati-1.png'),
(N'Samsung 870 EVO 500GB SATA SSD',2499.00,25,3,3,'https://productimages.hepsiburada.net/s/280/375-375/110000267058578.jpg'),
(N'Stanley Classic Vakumlu Termos 1L',1699.00,30,10,10,'https://www.ensarshop.com/idea/kc/70/myassets/products/686/termos-1-1.jpg?revision=1721741566'),
(N'Puma Phase Unisex Sırt Çantası',999.00,12,1,1,'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTLNzG5uecpgNyM-ezfkIbg4tq3ZymlBE7BkQ&s');

INSERT INTO Siparis (MusteriID, SiparisTarihi, Durum) VALUES
(1,'2026-03-10','Teslim'),(2,'2026-03-12','Kargoda'),
(3,'2026-03-15','Hazirlaniyor'),(4,'2026-03-18','Teslim'),
(5,'2026-03-20','Iptal'),(6,'2026-04-01','Teslim'),
(7,'2026-04-05','Kargoda'),(8,'2026-04-10','Hazirlaniyor'),
(9,'2026-04-15','Teslim'),(10,'2026-04-20','Kargoda');

INSERT INTO SiparisDetay (SiparisID, UrunID, Adet, BirimFiyat) VALUES
(1,1,2,1999.90),(1,6,1,649.00),(2,3,1,399.00),
(3,5,1,799.00),(4,7,2,299.00),(5,2,1,2199.90),
(6,9,1,799.00),(7,4,1,279.90),(8,8,2,249.00),
(9,10,1,449.90),(10,6,3,649.00);

INSERT INTO Yorum (UrunID, MusteriID, Puan, Metin) VALUES
(1,1,5,N'Forma kalitesi çok iyi, tam beden geldi.'),
(1,3,4,N'Güzel ürün ama kargo biraz geç geldi.'),
(5,2,5,N'Klavye harika, tuşların sesi çok iyi.'),
(6,4,4,N'Mouse iyi çalışıyor ama kablosu kısa.'),
(3,5,3,N'Paspas idare eder, fiyatına göre normal.'),
(7,6,5,N'Okey seti çok sağlam, tavsiye ederim.'),
(9,7,4,N'Nevresim yumuşak ama rengi biraz soldu.'),
(2,8,5,N'Orijinal ürün, hızlı kargo teşekkürler.'),
(8,9,4,N'Satranç tahtası kaliteli, memnunum.'),
(10,10,3,N'Çaydanlık düşündüğümden küçük çıktı.'),
(13,2,5,N'Soru bankası sınava çalışmak için çok faydalı.'),
(12,4,4,N'Kılıf telefona tam oturuyor.');

INSERT INTO UrunVaryant (UrunID, Beden, Renk, Stok) VALUES
(1,N'S',N'Lacivert-Sarı',12),(1,N'M',N'Lacivert-Sarı',18),
(1,N'L',N'Lacivert-Sarı',14),(1,N'XL',N'Lacivert-Sarı',9),
(2,N'S',N'Sarı-Kırmızı',8),(2,N'M',N'Sarı-Kırmızı',15),
(2,N'L',N'Sarı-Kırmızı',12),(2,N'XL',N'Sarı-Kırmızı',6),
(16,N'S',N'Siyah-Beyaz',10),(16,N'M',N'Siyah-Beyaz',14),
(16,N'L',N'Siyah-Beyaz',11),(16,N'XL',N'Siyah-Beyaz',7),
(5,NULL,N'Blue Switch',8),(5,NULL,N'Red Switch',5),(5,NULL,N'Brown Switch',4),
(12,NULL,N'Şeffaf',30),(12,NULL,N'Siyah',25),(12,NULL,N'Bordo',15),(12,NULL,N'Lacivert',18),
(9,NULL,N'Beyaz',8),(9,NULL,N'Mavi',5),(9,NULL,N'Gri',7),
(21,N'40',N'Beyaz-Siyah',4),(21,N'41',N'Beyaz-Siyah',6),
(21,N'42',N'Beyaz-Siyah',8),(21,N'43',N'Beyaz-Siyah',5),(21,N'44',N'Beyaz-Siyah',3);
GO

-- =====================================================================
-- HIZLI TEST
-- EXEC sp_SepetToplami 1;
-- EXEC sp_MusteriOzet 1;
-- EXEC sp_SatisRaporu;
-- SELECT * FROM vw_SiparisOzeti;
-- SELECT * FROM vw_KritikStok;
-- SELECT * FROM vw_SatisDetaylari;
-- UPDATE Siparis SET Durum='Iptal' WHERE SiparisID=2;
-- =====================================================================
