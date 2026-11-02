require "rails_helper"

RSpec.describe ProhibitedItems::Normalizer do
  describe ".text" do
    it "downcases and turns punctuation into single spaces" do
      expect(described_class.text("AK-47,  NEW!!")).to eq("ak 47 new")
    end

    it "turns Arabic ي / ى / ك into Persian ی / ک" do
      expect(described_class.text("ترياك")).to eq("تریاک")
      expect(described_class.text("موسى")).to eq("موسی")
    end

    it "folds alef forms and teh marbuta" do
      expect(described_class.text("آبجو")).to eq("ابجو")
      expect(described_class.text("أفيون إ")).to eq("افیون ا")
      expect(described_class.text("مدرسة")).to eq("مدرسه")
    end

    it "strips harakat, tatweel, ZWNJ and bidi marks" do
      expect(described_class.text("چَرْس")).to eq("چرس")
      expect(described_class.text("تـــریاک")).to eq("تریاک")
      expect(described_class.text("شرط‌بندی")).to eq("شرطبندی")
      expect(described_class.text("‏قمار‎")).to eq("قمار")
    end

    it "turns Persian and Arabic-Indic digits into ASCII" do
      expect(described_class.text("ای کی ۴۷ و ٤٧")).to eq("ای کی 47 و 47")
    end

    it "folds Arabic presentation forms (NFKC)" do
      expect(described_class.text("ﻻبرای")).to eq("لابرای")
    end

    it "keeps Pashto letters apart" do
      expect(described_class.text("ټوپک ګولۍ")).to eq("ټوپک ګولۍ")
    end
  end

  describe ".term" do
    it "normalizes like text and keeps a trailing star" do
      expect(described_class.term(" هيروئين* ")).to eq("هیروئین*")
      expect(described_class.term("Fake  Passport")).to eq("fake passport")
    end

    it "is blank for a bare star" do
      expect(described_class.term("*")).to eq("")
    end
  end
end
