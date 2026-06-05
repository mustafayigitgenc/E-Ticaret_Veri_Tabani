-- =====================================================================
-- miyshop E-Ticaret Veritabanı Sistemi — Tam Kurulum Betiği
-- Grup: 241307022 Mustafa Yiğit Genç — 241307056 İbrahim Akkuş
-- Ders: TBL331 Veritabanı Yönetim Sistemleri (2025-2026 Bahar)
-- Geliştirme Ortamı: Microsoft SQL Server 2022 + SSMS
-- Açıklama: Sıfırdan tek seferde çalıştırılır.
-- =====================================================================

CREATE DATABASE ETicaretDB;
GO
USE ETicaretDB;
GO

-- =====================================================================
-- BÖLÜM 1: TABLOLAR (8 ADET)
-- 5NF uyumlu, veri tekrarı önlenmiş, FK ile ilişkilendirilmiş
-- =====================================================================

-- Ürün kategorileri
CREATE TABLE Kategori (
    KategoriID  INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(50) NOT NULL UNIQUE
);

-- Sisteme kayıtlı müşteriler
CREATE TABLE Musteri (
    MusteriID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad           NVARCHAR(50)  NOT NULL,
    Soyad        NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(100) NOT NULL UNIQUE,
    KayitTarihi  DATE NOT NULL DEFAULT GETDATE()
);

-- Platforma kayıtlı satıcı mağazalar
CREATE TABLE Magaza (
    MagazaID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(100) NOT NULL UNIQUE,
    Sehir       NVARCHAR(50)  NOT NULL,
    Puan        DECIMAL(2,1)  NOT NULL DEFAULT 0 CHECK (Puan >= 0 AND Puan <= 5),
    KayitTarihi DATE NOT NULL DEFAULT GETDATE()
);

-- Satışa sunulan ürünler (kategori ve mağazaya bağlı)
CREATE TABLE Urun (
    UrunID      INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(120) NOT NULL,
    Fiyat       DECIMAL(10,2) NOT NULL CHECK (Fiyat > 0),
    StokAdedi   INT NOT NULL DEFAULT 0 CHECK (StokAdedi >= 0),
    KategoriID  INT NOT NULL,
    MagazaID    INT NOT NULL,
    GorselURL   NVARCHAR(300),
    CONSTRAINT FK_Urun_Kategori FOREIGN KEY (KategoriID) REFERENCES Kategori(KategoriID),
    CONSTRAINT FK_Urun_Magaza   FOREIGN KEY (MagazaID)   REFERENCES Magaza(MagazaID)
);

-- Ürün beden/renk/tür varyantları ve varyanta özel stok
CREATE TABLE UrunVaryant (
    VaryantID   INT IDENTITY(1,1) PRIMARY KEY,
    UrunID      INT NOT NULL,
    Beden       NVARCHAR(20),
    Renk        NVARCHAR(30),
    Stok        INT NOT NULL DEFAULT 0 CHECK (Stok >= 0),
    CONSTRAINT FK_Varyant_Urun FOREIGN KEY (UrunID) REFERENCES Urun(UrunID),
    CONSTRAINT CK_Varyant_BedenveyaRenk CHECK (Beden IS NOT NULL OR Renk IS NOT NULL)
);

-- Müşteri siparişleri
CREATE TABLE Siparis (
    SiparisID     INT IDENTITY(1,1) PRIMARY KEY,
    MusteriID     INT NOT NULL,
    SiparisTarihi DATETIME NOT NULL DEFAULT GETDATE(),
    Durum         NVARCHAR(20) NOT NULL DEFAULT 'Hazirlaniyor'
                  CHECK (Durum IN ('Hazirlaniyor','Kargoda','Teslim','Iptal')),
    CONSTRAINT FK_Siparis_Musteri FOREIGN KEY (MusteriID) REFERENCES Musteri(MusteriID)
);

-- Sipariş detayları: Sipariş–Ürün N:N ilişkisini çözen ara tablo
-- BirimFiyat: sipariş anındaki fiyatı saklar (sonradan değişebilir)
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

-- Müşteri ürün yorumları
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
-- BÖLÜM 2: INDEXLER (6 ADET)
-- Sık JOIN'lenen FK kolonlarında sorgu performansını artırır
-- =====================================================================
CREATE INDEX IX_Urun_Kategori   ON Urun(KategoriID);
CREATE INDEX IX_Urun_Magaza     ON Urun(MagazaID);
CREATE INDEX IX_Siparis_Musteri ON Siparis(MusteriID);
CREATE INDEX IX_Detay_Siparis   ON SiparisDetay(SiparisID);
CREATE INDEX IX_Yorum_Urun      ON Yorum(UrunID);
CREATE INDEX IX_Yorum_Musteri   ON Yorum(MusteriID);
GO

-- =====================================================================
-- BÖLÜM 3: TRIGGER'LAR (2 ADET)
-- =====================================================================

-- Sipariş verilince hem genel ürün stoğu hem varyant stoğu düşer.
-- inserted sanal tablosu + JOIN kullanıldı: toplu INSERT'te de çalışır.
-- Stok sıfırın altına düşecekse CHECK kısıtı işlemi engeller (rollback).
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

-- Sipariş 'Iptal' yapılınca stok geri iade edilir.
-- inserted (yeni) ve deleted (eski) karşılaştırması:
-- yalnızca yeni iptal edilenler tetiklenir; zaten iptal olan tekrar stoğu şişiremez.
CREATE TRIGGER trg_IptalStokGeri
ON Siparis
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE u SET u.StokAdedi = u.StokAdedi + sd.Adet
    FROM Urun u
    JOIN SiparisDetay sd ON u.UrunID    = sd.UrunID
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
-- BÖLÜM 4: STORED PROCEDURE'LAR (3 ADET)
-- =====================================================================

-- Verilen siparişin toplam tutarını döndürür (Adet × BirimFiyat toplamı)
CREATE PROCEDURE sp_SepetToplami
    @SiparisID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SUM(Adet * BirimFiyat) AS ToplamTutar
    FROM SiparisDetay WHERE SiparisID = @SiparisID;
END;
GO

-- Müşterinin tüm siparişlerini ve her siparişin tutarını listeler
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

-- Kategoriye göre sipariş sayısı, satılan adet ve toplam ciroyu döndürür
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
-- BÖLÜM 5: VIEW'LAR (3 ADET)
-- =====================================================================

-- Müşteri + sipariş + detay + ürün birleşimi; raporlamada tekrar JOIN gerekmez
CREATE VIEW vw_SiparisOzeti AS
SELECT s.SiparisID, m.Ad+' '+m.Soyad AS Musteri, s.SiparisTarihi,
       u.Ad AS Urun, sd.Adet, sd.BirimFiyat, (sd.Adet*sd.BirimFiyat) AS SatirTutar
FROM Siparis s
JOIN Musteri m       ON s.MusteriID  = m.MusteriID
JOIN SiparisDetay sd ON s.SiparisID  = sd.SiparisID
JOIN Urun u          ON sd.UrunID    = u.UrunID;
GO

-- Stoğu 10'un altına düşen ürünler; tedarik yönetimi için
CREATE VIEW vw_KritikStok AS
SELECT u.UrunID, u.Ad, u.StokAdedi, k.Ad AS Kategori
FROM Urun u JOIN Kategori k ON u.KategoriID = k.KategoriID
WHERE u.StokAdedi < 10;
GO

-- Tüm satış verilerini tek sorguda birleştiren kapsamlı rapor view'ı
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
-- BÖLÜM 6: TEST VERİLERİ
-- Ekleme sırası FK bağımlılığına göre: bağımsız → bağımlı tablolar
-- =====================================================================

-- KATEGORİ (10)
INSERT INTO Kategori (Ad) VALUES
(N'Giyim & Moda'),
(N'Oto Aksesuar'),
(N'Elektronik'),
(N'Oyun & Hobi'),
(N'Ev & Yaşam'),
(N'Spor & Outdoor'),
(N'Telefon & Tablet'),
(N'Kitap & Kırtasiye'),
(N'Bahçe & Yapı Market'),
(N'Mutfak & Gıda');

-- MÜŞTERİ (10)
INSERT INTO Musteri (Ad, Soyad, Email) VALUES
(N'İbrahim',  N'Akkuş',   'ibrahim.akkus@mail.com'),
(N'Buket',    N'Yılmaz',  'buket.yilmaz@mail.com'),
(N'Sude',     N'Demir',   'sude.demir@mail.com'),
(N'Furkan',   N'Kaya',    'furkan.kaya@mail.com'),
(N'Elif',     N'Şahin',   'elif.sahin@mail.com'),
(N'Mert',     N'Aydın',   'mert.aydin@mail.com'),
(N'Zeynep',   N'Çelik',   'zeynep.celik@mail.com'),
(N'Emre',     N'Doğan',   'emre.dogan@mail.com'),
(N'Merve',    N'Arslan',  'merve.arslan@mail.com'),
(N'Kerem',    N'Öztürk',  'kerem.ozturk@mail.com');

-- MAĞAZA (10) — marketplace satıcı nickname tarzı
INSERT INTO Magaza (Ad, Sehir, Puan) VALUES
(N'SportZone',     N'İstanbul',   4.5),
(N'OtoPlus',       N'Kocaeli',    4.2),
(N'TechNova',      N'Ankara',     4.8),
(N'HobiDünyam',    N'İzmir',      4.0),
(N'HomeStyle',     N'Bursa',      3.9),
(N'OutdoorFlex',   N'Antalya',    4.6),
(N'MobilPro',      N'İstanbul',   4.1),
(N'KitapEvim',     N'Eskişehir',  4.7),
(N'BahçeExpress',  N'Konya',      3.8),
(N'MutfakDepo',    N'Adana',      4.3);

-- ÜRÜN (30) — bazı stoklar bilerek 10 altı (vw_KritikStok testi)
INSERT INTO Urun (Ad, Fiyat, StokAdedi, KategoriID, MagazaID, GorselURL) VALUES
(N'Fenerbahçe Yeni Sezon Çubuklu Forma',  1299.90, 50, 1, 1, 'https://placehold.co/300x300/1a1a2e/white?text=FB+Forma'),
(N'Galatasaray Deplasman Forma 2025',      1349.00, 40, 1, 1, 'https://placehold.co/300x300/ffc107/black?text=GS+Forma'),
(N'Renault Clio Uyumlu Havuzlu Paspas',     449.00, 30, 2, 2, 'https://placehold.co/300x300/2d6a4f/white?text=Clio+Paspas'),
(N'Fiat Linea Sis Farı (Sağ)',              389.90,  7, 2, 2, 'https://placehold.co/300x300/344e41/white?text=Sis+Fari'),
(N'Mekanik Oyuncu Klavyesi RGB',            899.50, 15, 3, 3, 'https://placehold.co/300x300/e94560/white?text=Klavye+RGB'),
(N'Kablosuz Optik Mouse 1600 DPI',          249.90, 60, 3, 3, 'https://placehold.co/300x300/0077b6/white?text=Mouse'),
(N'101 Plus Okey Seti',                     329.00, 35, 4, 4, 'https://placehold.co/300x300/6a0572/white?text=Okey+Seti'),
(N'Ahşap Satranç Takımı',                   279.50,  8, 4, 4, 'https://placehold.co/300x300/8b4513/white?text=Satranc'),
(N'4 Kişilik Pamuklu Nevresim Takımı',      699.00, 18, 5, 5, 'https://placehold.co/300x300/c77dff/white?text=Nevresim'),
(N'Paslanmaz Çelik Çaydanlık',              459.90, 22, 10, 10, 'https://placehold.co/300x300/adb5bd/black?text=Caydanlik'),
(N'Bluetooth Spor Kulaklık',                349.90, 45, 6, 6, 'https://placehold.co/300x300/00b4d8/white?text=Kulaklik'),
(N'iPhone Uyumlu Şeffaf Kılıf',             129.90, 80, 7, 7, 'https://placehold.co/300x300/48cae4/white?text=Kilif'),
(N'KPSS Genel Kültür Soru Bankası',         189.00, 55, 8, 8, 'https://placehold.co/300x300/f4a261/black?text=KPSS+Kitap'),
(N'Bahçe Sulama Hortumu 30m',               274.90, 20, 9, 9, 'https://placehold.co/300x300/588157/white?text=Hortum'),
(N'Takım Elbise Kıyafet Koruyucu',           89.90, 100, 1, 1, 'https://placehold.co/300x300/264653/white?text=Koruyucu'),
(N'Trabzonspor 2025 Forma',                1199.90, 35, 1, 1, 'https://placehold.co/300x300/722f37/white?text=TS+Forma'),
(N'Audi A3 Uyumlu Ön Panjur Çerçevesi',     549.00, 12, 2, 2, 'https://placehold.co/300x300/1c1c1c/white?text=Audi+A3'),
(N'27 inç Oyuncu Monitörü 144Hz',          4299.00,  8, 3, 3, 'https://placehold.co/300x300/00008b/white?text=Monitor+144Hz'),
(N'Monopoly Türkiye Baskısı',               449.90,  5, 4, 4, 'https://placehold.co/300x300/c0392b/white?text=Monopoly'),
(N'Boyun Yastığı Memory Foam',              389.00, 25, 5, 5, 'https://placehold.co/300x300/a0c4ff/black?text=Memory+Foam'),
(N'Adidas Superstar Spor Ayakkabı',        2199.00, 20, 6, 6, 'https://placehold.co/300x300/f0f0f0/black?text=Superstar'),
(N'Samsung 25W USB-C Hızlı Şarj Aleti',     249.90, 70, 7, 7, 'https://placehold.co/300x300/1428a0/white?text=25W+Sarj'),
(N'Türkçe-İngilizce Büyük Sözlük',          179.00, 40, 8, 8, 'https://placehold.co/300x300/2c3e50/white?text=Sozluk'),
(N'Bonsai Toprağı 5 Litre',                 129.90, 30, 9, 9, 'https://placehold.co/300x300/3d5a2b/white?text=Bonsai+Toprak'),
(N'Mini Blender 350W Smoothie Makinesi',    599.00, 15, 10, 10, 'https://placehold.co/300x300/e74c3c/white?text=Mini+Blender'),
(N'Converse Chuck Taylor All Star Hi Siyah', 1599.90, 18, 1, 1, 'https://placehold.co/300x300/1c1c1c/white?text=Converse'),
(N'Garmin Forerunner 55 GPS Koşu Saati',    4299.00, 10, 6, 6, 'https://placehold.co/300x300/007cc3/white?text=Garmin+F55'),
(N'Kingston Fury Beast 16GB DDR5 5200MHz',  1849.00, 25, 3, 3, 'https://placehold.co/300x300/cc0000/white?text=DDR5+16GB'),
(N'Stanley Classic Vakumlu Termos 1L',       699.00, 30, 10, 10, 'https://placehold.co/300x300/1a6b3c/white?text=Stanley+1L'),
(N'Fjällräven Kånken Mini Sırt Çantası',   1699.00, 12, 1, 1, 'https://placehold.co/300x300/b5651d/white?text=Kanken+Mini');

-- SİPARİŞ (10)
INSERT INTO Siparis (MusteriID, SiparisTarihi, Durum) VALUES
(1, '2026-03-10', 'Teslim'),
(2, '2026-03-12', 'Kargoda'),
(3, '2026-03-15', 'Hazirlaniyor'),
(4, '2026-03-18', 'Teslim'),
(5, '2026-03-20', 'Iptal'),
(6, '2026-04-01', 'Teslim'),
(7, '2026-04-05', 'Kargoda'),
(8, '2026-04-10', 'Hazirlaniyor'),
(9, '2026-04-15', 'Teslim'),
(10,'2026-04-20', 'Kargoda');

-- SİPARİŞ DETAY (11) — INSERT sırasında trg_StokDus tetiklenir
INSERT INTO SiparisDetay (SiparisID, UrunID, Adet, BirimFiyat) VALUES
(1, 1, 2, 1299.90),
(1, 6, 1,  249.90),
(2, 3, 1,  449.00),
(3, 5, 1,  899.50),
(4, 7, 2,  329.00),
(5, 2, 1, 1349.00),
(6, 9, 1,  699.00),
(7, 4, 1,  389.90),
(8, 8, 2,  279.50),
(9, 10,1,  459.90),
(10,6, 3,  249.90);

-- YORUM (12)
INSERT INTO Yorum (UrunID, MusteriID, Puan, Metin) VALUES
(1, 1, 5, N'Forma kalitesi çok iyi, tam beden geldi.'),
(1, 3, 4, N'Güzel ürün ama kargo biraz geç geldi.'),
(5, 2, 5, N'Klavye harika, tuşların sesi çok iyi.'),
(6, 4, 4, N'Mouse iyi çalışıyor ama kablosu kısa.'),
(3, 5, 3, N'Paspas idare eder, fiyatına göre normal.'),
(7, 6, 5, N'Okey seti çok sağlam, tavsiye ederim.'),
(9, 7, 4, N'Nevresim yumuşak ama rengi biraz soldu.'),
(2, 8, 5, N'Orijinal ürün, hızlı kargo teşekkürler.'),
(8, 9, 4, N'Satranç tahtası kaliteli, memnunum.'),
(10,10, 3, N'Çaydanlık düşündüğümden küçük çıktı.'),
(13, 2, 5, N'Soru bankası sınava çalışmak için çok faydalı.'),
(12, 4, 4, N'Kılıf telefona tam oturuyor.');

-- ÜRÜN VARYANTLARI (27)
INSERT INTO UrunVaryant (UrunID, Beden, Renk, Stok) VALUES
(1, N'S',  N'Lacivert-Sarı', 12),(1, N'M',  N'Lacivert-Sarı', 18),
(1, N'L',  N'Lacivert-Sarı', 14),(1, N'XL', N'Lacivert-Sarı',  9),
(2, N'S',  N'Sarı-Kırmızı',  8),(2, N'M',  N'Sarı-Kırmızı', 15),
(2, N'L',  N'Sarı-Kırmızı', 12),(2, N'XL', N'Sarı-Kırmızı',  6),
(16,N'S',  N'Bordo-Lacivert',10),(16,N'M',  N'Bordo-Lacivert',14),
(16,N'L',  N'Bordo-Lacivert',11),(16,N'XL', N'Bordo-Lacivert', 7),
(5, NULL, N'Blue Switch (Sessiz)', 8),
(5, NULL, N'Red Switch (Lineer)',  5),
(5, NULL, N'Brown Switch (Taktil)',4),
(12,NULL, N'Şeffaf', 30),(12,NULL, N'Siyah',  25),
(12,NULL, N'Bordo',  15),(12,NULL, N'Lacivert',18),
(9, NULL, N'Beyaz',   8),(9, NULL, N'Mavi',    5),(9, NULL, N'Gri', 7),
(21,N'40', N'Beyaz-Siyah', 4),(21,N'41', N'Beyaz-Siyah', 6),
(21,N'42', N'Beyaz-Siyah', 8),(21,N'43', N'Beyaz-Siyah', 5),
(21,N'44', N'Beyaz-Siyah', 3);
GO

-- =====================================================================
-- HIZLI TEST SORGULARI (açıklama satırı olarak bırakıldı)
-- EXEC sp_SepetToplami 1;
-- EXEC sp_MusteriOzet 1;
-- EXEC sp_SatisRaporu;
-- SELECT * FROM vw_SiparisOzeti;
-- SELECT * FROM vw_KritikStok;
-- SELECT * FROM vw_SatisDetaylari;
-- UPDATE Siparis SET Durum='Iptal' WHERE SiparisID=2;
-- =====================================================================
