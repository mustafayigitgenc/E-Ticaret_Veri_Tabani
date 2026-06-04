-- =====================================================================
-- E-Ticaret Veritabanı Sistemi - Final Betiği
-- Grup: 241307022 Mustafa Yiğit Genç - 241307056 İbrahim Akkuş
-- Ders: TBL331 Veritabanı Yönetim Sistemleri (2025-2026 Bahar)
-- Açıklama: Bu betik, sıfırdan boş bir veritabanı oluşturmak ve 
--           gerekli tüm test verilerini eklemek üzere tasarlanmıştır. 
--           Yukarıdan aşağıya tek seferde çalıştırılabilir.
-- =====================================================================

CREATE DATABASE ETicaretDB;
GO

USE ETicaretDB;
GO

-- =====================================================================
-- 1. TABLOLARIN OLUŞTURULMASI (Toplam 7 Tablo)
-- =====================================================================

-- Kategori Tablosu: Ürünlerin ait olduğu temel grupları tutar.
CREATE TABLE Kategori (
    KategoriID  INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(50) NOT NULL UNIQUE       -- Aynı kategori adının tekrar eklenmesini önler
);

-- Müşteri Tablosu: Sisteme kayıtlı olan kullanıcıların bilgilerini tutar.
CREATE TABLE Musteri (
    MusteriID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad           NVARCHAR(50)  NOT NULL,
    Soyad        NVARCHAR(50)  NOT NULL,
    Email        NVARCHAR(100) NOT NULL UNIQUE,    -- Her e-posta adresi sistemde benzersiz olmalıdır
    KayitTarihi  DATE NOT NULL DEFAULT GETDATE()   -- Kayıt tarihi belirtilmezse otomatik olarak bugünü atar
);

-- Mağaza Tablosu: Sistem üzerinden satış yapan satıcıların/mağazaların bilgilerini tutar.
CREATE TABLE Magaza (
    MagazaID    INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(100) NOT NULL UNIQUE,     -- Mağaza adları benzersiz olmalıdır
    Sehir       NVARCHAR(50)  NOT NULL,
    Puan        DECIMAL(2,1)  NOT NULL DEFAULT 0 CHECK (Puan >= 0 AND Puan <= 5), -- Puanlama 0 ile 5 arasında olmalıdır
    KayitTarihi DATE NOT NULL DEFAULT GETDATE()
);

-- Ürün Tablosu: Mağazalar tarafından satılan ve belirli bir kategoriye ait olan ürünleri tutar.
CREATE TABLE Urun (
    UrunID      INT IDENTITY(1,1) PRIMARY KEY,
    Ad          NVARCHAR(120) NOT NULL,
    Fiyat       DECIMAL(10,2) NOT NULL CHECK (Fiyat > 0), -- Ürün fiyatı sıfırdan büyük olmalıdır
    StokAdedi   INT NOT NULL DEFAULT 0 CHECK (StokAdedi >= 0), -- Stok adedi eksi değerlere düşemez
    KategoriID  INT NOT NULL,
    MagazaID    INT NOT NULL,
    GorselURL   NVARCHAR(300),
    
    -- Kategori ve Mağaza tabloları ile olan ilişkiler (Foreign Key)
    CONSTRAINT FK_Urun_Kategori FOREIGN KEY (KategoriID) REFERENCES Kategori(KategoriID),
    CONSTRAINT FK_Urun_Magaza   FOREIGN KEY (MagazaID)   REFERENCES Magaza(MagazaID)
);

-- Sipariş Tablosu: Müşterilerin oluşturduğu temel sipariş başlıklarını tutar.
CREATE TABLE Siparis (
    SiparisID     INT IDENTITY(1,1) PRIMARY KEY,
    MusteriID     INT NOT NULL,
    SiparisTarihi DATETIME NOT NULL DEFAULT GETDATE(),
    Durum         NVARCHAR(20) NOT NULL DEFAULT 'Hazırlanıyor' 
                  CHECK (Durum IN ('Hazırlanıyor','Kargoda','Teslim','İptal')), -- Sadece belirlenen durumlar girilebilir
    
    -- Müşteri tablosu ile olan ilişki
    CONSTRAINT FK_Siparis_Musteri FOREIGN KEY (MusteriID) REFERENCES Musteri(MusteriID)
);

-- Sipariş Detay Tablosu: Siparişler ve Ürünler arasındaki çoka-çok (N:N) ilişkiyi çözümleyen ara tablodur.
CREATE TABLE SiparisDetay (
    DetayID     INT IDENTITY(1,1) PRIMARY KEY,
    SiparisID   INT NOT NULL,
    UrunID      INT NOT NULL,
    Adet        INT NOT NULL CHECK (Adet > 0),
    BirimFiyat  DECIMAL(10,2) NOT NULL CHECK (BirimFiyat > 0),  -- Satın alma anındaki fiyatı sabitler
    
    -- Sipariş ve Ürün tabloları ile olan ilişkiler
    CONSTRAINT FK_Detay_Siparis FOREIGN KEY (SiparisID) REFERENCES Siparis(SiparisID),
    CONSTRAINT FK_Detay_Urun    FOREIGN KEY (UrunID)    REFERENCES Urun(UrunID)
);

-- Yorum Tablosu: Müşterilerin satın aldıkları ürünlere yaptıkları değerlendirmeleri tutar.
CREATE TABLE Yorum (
    YorumID   INT IDENTITY(1,1) PRIMARY KEY,
    UrunID    INT NOT NULL,
    MusteriID INT NOT NULL,
    Puan      INT NOT NULL CHECK (Puan BETWEEN 1 AND 5),  -- Değerlendirme puanı 1 ile 5 yıldız arasında olmalıdır
    Metin     NVARCHAR(300),
    Tarih     DATE NOT NULL DEFAULT GETDATE(),
    
    CONSTRAINT FK_Yorum_Urun    FOREIGN KEY (UrunID)    REFERENCES Urun(UrunID),
    CONSTRAINT FK_Yorum_Musteri FOREIGN KEY (MusteriID) REFERENCES Musteri(MusteriID)
);
GO

-- =====================================================================
-- 2. İNDEKSLER (Performans Optimizasyonu)
-- =====================================================================
-- Açıklama: Tabloları birleştirirken (JOIN) ve filtreleme yaparken 
-- performansı artırmak amacıyla Yabancı Anahtar (Foreign Key) sütunlarına indeks eklenmiştir.

CREATE INDEX IX_Urun_Kategori   ON Urun(KategoriID);
CREATE INDEX IX_Urun_Magaza     ON Urun(MagazaID);
CREATE INDEX IX_Siparis_Musteri ON Siparis(MusteriID);
CREATE INDEX IX_Detay_Siparis   ON SiparisDetay(SiparisID);
CREATE INDEX IX_Yorum_Urun      ON Yorum(UrunID);
CREATE INDEX IX_Yorum_Musteri   ON Yorum(MusteriID);
GO

-- =====================================================================
-- 3. TETİKLEYİCİLER (TRIGGERS)
-- =====================================================================

-- Tetikleyici 1: Yeni Sipariş Verildiğinde Stoğu Düşür
-- Açıklama: SiparisDetay tablosuna yeni bir kayıt eklendiğinde, ilgili ürünün stoğunu otomatik olarak azaltır.
CREATE TRIGGER trg_StokDus 
ON SiparisDetay 
AFTER INSERT 
AS 
BEGIN
    SET NOCOUNT ON;
    -- 'inserted' tablosu, yeni eklenen satırları tutan geçici (sanal) bir tablodur.
    -- Toplu ekleme (Bulk Insert) işlemlerinde de hatasız çalışması için JOIN kullanılmıştır.
    UPDATE u
    SET u.StokAdedi = u.StokAdedi - i.Adet
    FROM Urun u
    INNER JOIN inserted i ON u.UrunID = i.UrunID;
END;
GO

-- Tetikleyici 2: Sipariş İptal Edildiğinde Stoğu Geri Yükle
-- Açıklama: Bir siparişin durumu 'İptal' olarak güncellendiğinde, o siparişteki ürünlerin adetlerini tekrar stoğa ekler.
CREATE TRIGGER trg_IptalStokGeri 
ON Siparis 
AFTER UPDATE 
AS 
BEGIN
    SET NOCOUNT ON;
    -- 'inserted' güncel veriyi, 'deleted' ise güncellemeden önceki veriyi tutar.
    -- Sadece durumu yeni 'İptal' olanları yakalamak için eski durumun 'İptal' OLMADIĞINI kontrol ediyoruz.
    UPDATE u
    SET u.StokAdedi = u.StokAdedi + sd.Adet
    FROM Urun u
    JOIN SiparisDetay sd ON u.UrunID = sd.UrunID
    JOIN inserted i      ON sd.SiparisID = i.SiparisID
    JOIN deleted  d      ON d.SiparisID  = i.SiparisID
    WHERE i.Durum = 'İptal' AND d.Durum <> 'İptal';
END;
GO

-- =====================================================================
-- 4. SAKLI YORDAMLAR (STORED PROCEDURES)
-- =====================================================================

-- Yordam 1: Belirli Bir Siparişin Toplam Tutarını Hesapla
CREATE PROCEDURE sp_SepetToplami
    @SiparisID INT 
AS 
BEGIN
    SET NOCOUNT ON;
    SELECT SUM(Adet * BirimFiyat) AS ToplamTutar
    FROM SiparisDetay
    WHERE SiparisID = @SiparisID;
END;
GO

-- Yordam 2: Belirli Bir Müşterinin Sipariş Geçmişini Getir
-- Açıklama: İlgili müşterinin tüm sipariş tarihlerini ve o siparişlerde harcadığı toplam tutarları listeler.
CREATE PROCEDURE sp_MusteriOzet
    @MusteriID INT 
AS 
BEGIN
    SET NOCOUNT ON;
    SELECT s.SiparisID,
           s.SiparisTarihi,
           SUM(sd.Adet * sd.BirimFiyat) AS SiparisTutari
    FROM Siparis s
    JOIN SiparisDetay sd ON s.SiparisID = sd.SiparisID
    WHERE s.MusteriID = @MusteriID
    GROUP BY s.SiparisID, s.SiparisTarihi;
END;
GO

-- =====================================================================
-- 5. GÖRÜNÜMLER (VIEWS)
-- =====================================================================

-- Görünüm 1: Detaylı Sipariş Özeti
-- Açıklama: 4 farklı tabloyu birleştirerek, siparişleri son kullanıcı veya yönetici için okunaklı bir rapora dönüştürür.
CREATE VIEW vw_SiparisOzeti AS 
SELECT s.SiparisID,
       m.Ad + ' ' + m.Soyad     AS Musteri,
       s.SiparisTarihi,
       u.Ad                     AS Urun,
       sd.Adet,
       sd.BirimFiyat,
       (sd.Adet * sd.BirimFiyat) AS SatirTutari
FROM Siparis s
JOIN Musteri m       ON s.MusteriID = m.MusteriID
JOIN SiparisDetay sd ON s.SiparisID = sd.SiparisID
JOIN Urun u          ON sd.UrunID   = u.UrunID;
GO

-- Görünüm 2: Kritik Stok Seviyesi Uyarı Raporu
-- Açıklama: Tedarik sürecini yönetmek için stoğu 10 adedin altına düşen ürünleri listeler.
CREATE VIEW vw_KritikStok AS 
SELECT u.UrunID, u.Ad, u.StokAdedi, k.Ad AS Kategori 
FROM Urun u
JOIN Kategori k ON u.KategoriID = k.KategoriID
WHERE u.StokAdedi < 10;
GO

-- =====================================================================
-- 6. ÖRNEK TEST VERİLERİNİN EKLENMESİ
-- =====================================================================
-- Not: Yabancı anahtar (Foreign Key) bağımlılıkları nedeniyle veri ekleme 
-- işlemi belirli bir sıraya göre yapılmalıdır. (Önce bağımsız tablolar)

-- KATEGORİ VERİLERİ (10 Adet)
INSERT INTO Kategori (Ad) 
VALUES ('Futbol Formaları'), ('Oto Aksesuar'), ('Bilgisayar & Çevre Birimleri'), 
       ('Oyun & Hobi'), ('Ev & Yaşam'), ('Spor & Outdoor'), 
       ('Telefon Aksesuarı'), ('Kitap & Kırtasiye'), ('Bahçe & Yapı Market'), ('Mutfak Gereçleri');

-- MÜŞTERİ VERİLERİ (10 Adet)
INSERT INTO Musteri (Ad, Soyad, Email) 
VALUES ('İbrahim', 'Akkuş', 'ibrahim.akkus@mail.com'), ('Buket', 'Yılmaz', 'buket.yilmaz@mail.com'), 
       ('Sude', 'Demir', 'sude.demir@mail.com'), ('Furkan', 'Kaya', 'furkan.kaya@mail.com'), 
       ('Elif', 'Şahin', 'elif.sahin@mail.com'), ('Mert', 'Aydın', 'mert.aydin@mail.com'), 
       ('Zeynep', 'Çelik', 'zeynep.celik@mail.com'), ('Emre', 'Doğan', 'emre.dogan@mail.com'), 
       ('Merve', 'Arslan', 'merve.arslan@mail.com'), ('Kerem', 'Öztürk', 'kerem.ozturk@mail.com');

-- MAĞAZA VERİLERİ (10 Adet)
INSERT INTO Magaza (Ad, Sehir, Puan) 
VALUES ('Spor Dünyası', 'İstanbul', 4.5), ('OtoParça Merkezi', 'Kocaeli', 4.2), 
       ('TeknoMarket', 'Ankara', 4.8), ('Hobi Dükkanı', 'İzmir', 4.0), 
       ('Ev Yaşam Store', 'Bursa', 3.9), ('Kampçım Outdoor', 'Antalya', 4.6), 
       ('Mobil Aksesuar', 'İstanbul', 4.1), ('Kitap Köşesi', 'Eskişehir', 4.7), 
       ('Bahçe Market', 'Konya', 3.8), ('Mutfak Sarayı', 'Adana', 4.3);

-- ÜRÜN VERİLERİ (15 Adet) 
-- Not: Kritik stok görünümü (vw_KritikStok) test edilebilmesi için bazı stoklar bilerek 10'un altında tutulmuştur.
INSERT INTO Urun (Ad, Fiyat, StokAdedi, KategoriID, MagazaID, GorselURL) 
VALUES 
('Fenerbahçe Yeni Sezon Çubuklu Forma', 1299.90, 50, 1, 1, 'https://placehold.co/300x300/1a1a2e/white?text=FB+Forma'), 
('Galatasaray Deplasman Forma 2025', 1349.00, 40, 1, 1, 'https://placehold.co/300x300/ffc107/black?text=GS+Forma'), 
('Renault Clio Uyumlu Havuzlu Paspas', 449.00, 30, 2, 2, 'https://placehold.co/300x300/2d6a4f/white?text=Clio+Paspas'), 
('Fiat Linea Sis Farı (Sağ)', 389.90, 7, 2, 2, 'https://placehold.co/300x300/344e41/white?text=Sis+Fari'), 
('Mekanik Oyuncu Klavyesi RGB', 899.50, 15, 3, 3, 'https://placehold.co/300x300/e94560/white?text=Klavye+RGB'), 
('Kablosuz Optik Mouse 1600 DPI', 249.90, 60, 3, 3, 'https://placehold.co/300x300/0077b6/white?text=Mouse'), 
('101 Plus Okey Seti', 329.00, 35, 4, 4, 'https://placehold.co/300x300/6a0572/white?text=Okey+Seti'), 
('Ahşap Satranç Takımı', 279.50, 8, 4, 4, 'https://placehold.co/300x300/8b4513/white?text=Satranc'), 
('4 Kişilik Pamuklu Nevresim Takımı', 699.00, 18, 5, 5, 'https://placehold.co/300x300/c77dff/white?text=Nevresim'), 
('Paslanmaz Çelik Çaydanlık', 459.90, 22, 10, 10, 'https://placehold.co/300x300/adb5bd/black?text=Caydanlik'), 
('Bluetooth Spor Kulaklık', 349.90, 45, 6, 6, 'https://placehold.co/300x300/00b4d8/white?text=Kulaklik'), 
('iPhone Uyumlu Şeffaf Kılıf', 129.90, 80, 7, 7, 'https://placehold.co/300x300/48cae4/white?text=Kilif'), 
('KPSS Genel Kültür Soru Bankası', 189.00, 55, 8, 8, 'https://placehold.co/300x300/f4a261/black?text=KPSS+Kitap'), 
('Bahçe Sulama Hortumu 30m', 274.90, 20, 9, 9, 'https://placehold.co/300x300/588157/white?text=Hortum'),
('Takım Elbise Kıyafet Koruyucu', 89.90, 100, 5, 5, 'https://placehold.co/300x300/264653/white?text=Koruyucu');

-- SİPARİŞ VERİLERİ (10 Adet)
-- Not: Test çeşitliliği sağlamak için farklı sipariş durumları kullanılmıştır.
INSERT INTO Siparis (MusteriID, SiparisTarihi, Durum) 
VALUES (1,  '2026-03-10', 'Teslim'), (2,  '2026-03-12', 'Kargoda'), 
       (3,  '2026-03-15', 'Hazırlanıyor'), (4,  '2026-03-18', 'Teslim'), 
       (5,  '2026-03-20', 'İptal'), (6,  '2026-04-01', 'Teslim'), 
       (7,  '2026-04-05', 'Kargoda'), (8,  '2026-04-10', 'Hazırlanıyor'), 
       (9,  '2026-04-15', 'Teslim'), (10, '2026-04-20', 'Kargoda');

-- SİPARİŞ DETAY VERİLERİ (11 Adet)
-- Not: Bu eklemeler yapıldığında 'trg_StokDus' tetikleyicisi devreye girecek ve ürün stokları otomatik düşecektir.
-- Çoka-çok ilişkiyi göstermek için 1 numaralı siparişe iki farklı ürün eklenmiştir.
INSERT INTO SiparisDetay (SiparisID, UrunID, Adet, BirimFiyat) 
VALUES (1, 1, 2, 1299.90), (1, 6, 1,  249.90), 
       (2, 3, 1,  449.00), (3, 5, 1,  899.50), 
       (4, 7, 2,  329.00), (5, 2, 1, 1349.00), 
       (6, 9, 1,  699.00), (7, 4, 1,  389.90), 
       (8, 8, 2,  279.50), (9, 10,1,  459.90), 
       (10,6, 3,  249.90);

-- YORUM VERİLERİ (12 Adet)
INSERT INTO Yorum (UrunID, MusteriID, Puan, Metin) 
VALUES (1,  1, 5, 'Forma kalitesi çok iyi, tam beden geldi.'), 
       (1,  3, 4, 'Güzel ürün ama kargo biraz geç geldi.'), 
       (5,  2, 5, 'Klavye harika, tuşların sesi çok iyi.'), 
       (6,  4, 4, 'Mouse iyi çalışıyor ama kablosu kısa.'), 
       (3,  5, 3, 'Paspas idare eder, fiyatına göre normal.'), 
       (7,  6, 5, 'Okey seti çok sağlam, kesinlikle tavsiye ederim.'), 
       (9,  7, 4, 'Nevresim yumuşak ama rengi yıkamada biraz soldu.'), 
       (2,  8, 5, 'Orijinal ürün, hızlı kargo teşekkürler.'), 
       (8,  9, 4, 'Satranç tahtası kaliteli, oldukça memnunum.'), 
       (10, 10, 3, 'Çaydanlık fotoğrafta göründüğünden daha küçük çıktı.'), 
       (13, 2, 5, 'Soru bankası sınava çalışmak için çok faydalı ve güncel.'), 
       (12, 4, 4, 'Kılıf telefona tam oturuyor, dokusu güzel.');
GO

-- =====================================================================
-- 7. HIZLI TEST SORGULARI
-- =====================================================================
-- Açıklama: Kurulan veritabanı yapılarını ve iş kurallarını test etmek için 
-- aşağıdaki satırların başındaki yorum işaretlerini (--) kaldırarak tek tek çalıştırabilirsiniz.

-- EXEC sp_SepetToplami 1;                                      -- 1 numaralı siparişin sepet toplamını hesaplar (Beklenen: 2849.70)
-- EXEC sp_MusteriOzet 1;                                       -- 1 numaralı müşteri olan İbrahim'in sipariş geçmişini getirir
-- SELECT * FROM vw_SiparisOzeti;                               -- Tüm siparişleri tek bir tabloda okunaklı biçimde listeler
-- SELECT * FROM vw_KritikStok;                                 -- Stoğu 10'un altına düşen uyarı niteliğindeki ürünleri getirir
-- SELECT Ad, StokAdedi FROM Urun ORDER BY StokAdedi;           -- Siparişler girildikten sonra düşen stok durumlarını gösterir
-- UPDATE Siparis SET Durum='İptal' WHERE SiparisID=2;          -- İptal tetikleyicisini test eder (2 numaralı siparişteki ürünün stoğu geri artmalıdır)
