/// Authoritative vaccine master data shared by immunization forms, filters,
/// patient history, and the BHW vaccine table. Stored records keep their
/// original label; this table controls selectable/reference labels.
class ImmunizationVaccineDefinition {
  final String name;
  final String code;
  final String doseSequence;
  final bool active;

  const ImmunizationVaccineDefinition({
    required this.name,
    required this.code,
    required this.doseSequence,
    this.active = true,
  });
}

const List<ImmunizationVaccineDefinition> kImmunizationVaccineMaster =
    <ImmunizationVaccineDefinition>[
      ImmunizationVaccineDefinition(
        name: 'BCG Vaccine',
        code: 'BCG',
        doseSequence: 'Dose 1',
      ),
      ImmunizationVaccineDefinition(
        name: 'Hepatitis B',
        code: 'HEPB',
        doseSequence: 'Dose 1 / follow-up doses',
      ),
      ImmunizationVaccineDefinition(
        name: 'DPT Vaccine',
        code: 'DPT',
        doseSequence: 'Dose 1 / Dose 2 / Dose 3 / booster',
      ),
      ImmunizationVaccineDefinition(
        name: 'Polio Vaccine',
        code: 'POLIO',
        doseSequence: 'Dose 1 / follow-up doses',
      ),
      ImmunizationVaccineDefinition(
        name: 'MMR Vaccine',
        code: 'MMR',
        doseSequence: 'Dose 1 / Dose 2',
      ),
      ImmunizationVaccineDefinition(
        name: 'Varicella Vaccine',
        code: 'VAR',
        doseSequence: 'Dose 1 / Dose 2',
      ),
      ImmunizationVaccineDefinition(
        name: 'Influenza',
        code: 'FLU',
        doseSequence: 'Record dose as administered',
      ),
      ImmunizationVaccineDefinition(
        name: 'Pneumococcal',
        code: 'PNEU',
        doseSequence: 'Record dose as administered',
      ),
      ImmunizationVaccineDefinition(
        name: 'Pentavalent Vaccine',
        code: 'PENTA',
        doseSequence: 'Dose 1 / Dose 2 / Dose 3',
      ),
      ImmunizationVaccineDefinition(
        name: 'OPV',
        code: 'OPV',
        doseSequence: 'Dose 1 / follow-up doses',
      ),
      ImmunizationVaccineDefinition(
        name: 'IPV',
        code: 'IPV',
        doseSequence: 'Dose 1 / follow-up doses',
      ),
      ImmunizationVaccineDefinition(
        name: 'PCV',
        code: 'PCV',
        doseSequence: 'Dose 1 / Dose 2 / Dose 3',
      ),
      ImmunizationVaccineDefinition(
        name: 'Hepatitis A',
        code: 'HEPA',
        doseSequence: 'Dose 1 / Dose 2',
      ),
      ImmunizationVaccineDefinition(
        name: 'MR Vaccine',
        code: 'MR',
        doseSequence: 'Dose 1 / Dose 2',
      ),
      ImmunizationVaccineDefinition(
        name: 'Japanese Encephalitis (JE)',
        code: 'JE',
        doseSequence: 'Record dose as administered',
      ),
      ImmunizationVaccineDefinition(
        name: 'Tetanus-Diphtheria (Td)',
        code: 'TD',
        doseSequence: 'Record dose as administered',
      ),
      ImmunizationVaccineDefinition(
        name: 'HPV Vaccine',
        code: 'HPV',
        doseSequence: 'Dose 1 / Dose 2',
      ),
      ImmunizationVaccineDefinition(
        name: 'Pneumococcal Polysaccharide Vaccine (PPV)',
        code: 'PPV',
        doseSequence: 'Record dose as administered',
      ),
      ImmunizationVaccineDefinition(
        name: 'Rotavirus Vaccine',
        code: 'ROTA',
        doseSequence: 'Dose 1 / follow-up doses',
      ),
    ];

const List<String> kImmunizationVaccineOptions = <String>[
  'BCG Vaccine',
  'Hepatitis B',
  'DPT Vaccine',
  'Polio Vaccine',
  'MMR Vaccine',
  'Varicella Vaccine',
  'Influenza',
  'Pneumococcal',
  'Pentavalent Vaccine',
  'OPV',
  'IPV',
  'PCV',
  'Hepatitis A',
  'MR Vaccine',
  'Japanese Encephalitis (JE)',
  'Tetanus-Diphtheria (Td)',
  'HPV Vaccine',
  'Pneumococcal Polysaccharide Vaccine (PPV)',
  'Rotavirus Vaccine',
];
