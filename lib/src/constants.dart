class MosquitoSpecies {
  const MosquitoSpecies({
    required this.code,
    required this.fullName,
    required this.genus,
  });

  final String code; // AB, AG, AN, CQ
  final String fullName;
  final String genus; // Aedes, Anopheles, Culex
}

// Detector classes in order as specified
const List<MosquitoSpecies> kSpeciesList = [
  MosquitoSpecies(code: 'AB', fullName: 'Aedes albopictus', genus: 'Aedes'),
  MosquitoSpecies(code: 'AG', fullName: 'Aedes aegypti', genus: 'Aedes'),
  MosquitoSpecies(
    code: 'AN',
    fullName: 'Anopheles cracens',
    genus: 'Anopheles',
  ),
  MosquitoSpecies(
    code: 'CQ',
    fullName: 'Culex quinquefasciatus',
    genus: 'Culex',
  ),
];

const int kNumClasses = 4;
const List<String> kSpeciesCodes = ['AB', 'AG', 'AN', 'CQ'];
const List<String> kSpeciesFullNames = [
  'Aedes albopictus',
  'Aedes aegypti',
  'Anopheles cracens',
  'Culex quinquefasciatus',
];
const List<String> kSpeciesGenus = ['Aedes', 'Aedes', 'Anopheles', 'Culex'];

const List<String> kOzamizBarangays = <String>[
  '50th District (Pob.)',
  'Aguada (Pob.)',
  'Bacolod',
  'Bagakay',
  'Balintawak',
  'Banadero (Pob.)',
  'Baybay San Roque',
  'Baybay Santa Cruz',
  'Baybay Triunfo',
  'Bongbong',
  'Calabayan',
  'Capucao C.',
  'Capucao P.',
  'Carangan',
  'Carmen',
  'Catadman-Manabay',
  'Cavinte',
  'Cogon',
  'Dalapang',
  'Diguan',
  'Dimaluna',
  'Doña Consuelo',
  'Embargo',
  'Gala',
  'Gango',
  'Gotokan Daku',
  'Gotokan Diot',
  'Guimad',
  'Guingona',
  'Kinuman Norte',
  'Kinuman Sur',
  'Labinay',
  'Labo',
  'Lam-an',
  'Liposong',
  'Litapan',
  'Malaubang',
  'Manaka',
  'Maningcol',
  'Mentering',
  'Molicay',
  'Pantaon',
  'Pulot',
  'San Antonio',
  'Sangay Daku',
  'Sangay Diot',
  'Sinuza',
  'Stimson Abordo',
  'Tabid',
  'Tinago',
  'Trigos',
];

// Pipeline constants
const int kDetectSize = 640;
const int kCropSize = 224;
const double kCropMargin = 0.10;
const double kClaheClip = 2.0;
const int kClaheTiles = 8;
const double kUnsharpSigma = 1.0;
const double kUnsharpAmount = 0.4;
const double kDetConf = 0.25;
const double kDetIou = 0.45;
const double kClsConfMin = 0.70;
// ignore: constant_identifier_names
const double EXTRA_LARVA_CONF = 0.50;
const double kFocusThreshold = -1.0; // calibrate later
const int kMinCropPx = 16;
const int kMaxDetections = 3;
