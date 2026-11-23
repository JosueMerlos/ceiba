require "rails_helper"

RSpec.describe Imports::CsvReader do
  def read(bytes, max_rows: 5000, max_bytes: 5.megabytes) = described_class.call(bytes, max_rows:, max_bytes:)

  context "con un CSV exportado por Excel en español (Windows-1252, punto y coma, CRLF)" do
    let(:result) { read(File.binread(file_fixture_path)) }
    let(:file_fixture_path) { Rails.root.join("packs/platform/imports/spec/fixtures/excel-es.csv") }

    it "detecta la codificación y el separador" do
      expect([ result.encoding, result.separator ]).to eq([ "Windows-1252", ";" ])
    end

    it "normaliza los encabezados: minúsculas y sin acentos" do
      expect(result.headers).to eq(%w[nombre telefono correo notas])
    end

    it "convierte las celdas a UTF-8, respeta comillas con separador y saltos de línea, y omite las filas vacías" do
      expect(result.rows.map(&:cells)).to eq([
        [ "José Peña", "8800 0001", nil, "Prefiere la mañana" ],
        [ "Muñoz; Ana", "+505 8800 0002", "ana@ejemplo.com", "Línea 1\r\nLínea 2" ],
        [ "Ñico Ávila", "5.05888E+10", nil, nil ]
      ])
    end

    it "numera cada fila como su línea en la hoja (la vacía cuenta, el encabezado es la 1)" do
      expect(result.rows.map(&:number)).to eq([ 2, 3, 5 ])
    end
  end

  it "quita el BOM de UTF-8 y separa por comas" do
    result = read("\xEF\xBB\xBFnombre,teléfono\nAna,8800 0003\n".b)

    expect([ result.encoding, result.separator, result.headers, result.rows.first.cells ]).to eq([ "UTF-8", ",", %w[nombre telefono], [ "Ana", "8800 0003" ] ])
  end

  it "lee UTF-16 con BOM separado por tabuladores (Texto Unicode de Excel)" do
    bytes = "﻿nombre\tteléfono\r\nÁngela\t8800 0004\r\n".encode("UTF-16LE").b

    result = read(bytes)

    expect([ result.encoding, result.separator, result.rows.first.cells ]).to eq([ "UTF-16LE", "\t", [ "Ángela", "8800 0004" ] ])
  end

  it "no confunde las comas de un campo entre comillas con el separador" do
    result = read("\"nombre, completo\";telefono\n\"Ruiz, Ana\";8800 0005\n")

    expect([ result.separator, result.headers ]).to eq([ ";", %w[nombre_completo telefono] ])
  end

  describe "límites y archivos ilegibles" do
    it "acepta exactamente el máximo de filas" do
      bytes = "nombre\n" + Array.new(3) { |index| "Persona #{index}\n" }.join

      expect(read(bytes, max_rows: 3).rows.size).to eq(3)
    end

    it "rechaza una fila más del máximo, sin contar las vacías" do
      bytes = "nombre\n" + Array.new(4) { |index| "Persona #{index}\n" }.join + "\n\n"

      expect { read(bytes, max_rows: 3) }.to raise_error(Imports::TooManyRows) { |error| expect([ error.rows, error.max_rows ]).to eq([ 4, 3 ]) }
    end

    it "rechaza un archivo por encima del tamaño máximo antes de decodificarlo" do
      expect { read("nombre\n" + ("x" * 20), max_bytes: 10) }.to raise_error(Imports::FileTooLarge)
    end

    it "rechaza un archivo sin filas de datos" do
      expect { read("nombre;telefono\r\n;\r\n") }.to raise_error(Imports::EmptyFile)
    end

    it "rechaza un archivo vacío" do
      expect { read("") }.to raise_error(Imports::EmptyFile)
    end

    it "rechaza un binario (bytes nulos)" do
      expect { read("PK\x03\x04\x00\x00nombre\n".b) }.to raise_error(Imports::UnreadableFile)
    end

    it "rechaza un CSV mal formado (comilla sin cerrar)" do
      expect { read("nombre;telefono\n\"Ana;8800 0006\n") }.to raise_error(Imports::UnreadableFile)
    end

    it "rechaza encabezados repetidos tras normalizarlos" do
      expect { read("Teléfono;telefono\n8800 0007;8800 0008\n") }.to raise_error(Imports::DuplicateColumns)
    end
  end
end
