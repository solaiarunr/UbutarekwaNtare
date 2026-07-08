import UIKit

final class DestinationArrivalViewController: UIViewController {
    private let mineral: MineralsListItem

    init(mineral: MineralsListItem) {
        self.mineral = mineral
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        setupCard()
    }

    private func setupCard() {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = AppColors.gray
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let discoveryLabel = makeCaptionLabel("DISCOVERY TYPE")
        let titleLabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: 26)
        titleLabel.textColor = UIColor(red: 0.11, green: 0.37, blue: 0.13, alpha: 1)
        titleLabel.text = formattedDiscoveryType()

        let mineralCard = makeInfoCard(
            caption: "MINERAL",
            value: formattedMineralTypeName(),
            captionColor: UIColor(red: 0.72, green: 0.53, blue: 0.04, alpha: 1),
            valueColor: UIColor(red: 0.55, green: 0.41, blue: 0.08, alpha: 1)
        )

        let geoCard = makeGeoCard()

        let sizeCard = makeMeasurementCard(
            caption: "EST. SIZE",
            value: formatMeasurement(mineral.sizeCubicMeters),
            unit: "m³"
        )
        let depthCard = makeMeasurementCard(
            caption: "DEPTH",
            value: mineral.depthCm.map { formatMeasurement($0) } ?? "—",
            unit: "cm"
        )

        let measurementsRow = UIStackView(arrangedSubviews: [sizeCard, depthCard])
        measurementsRow.axis = .horizontal
        measurementsRow.spacing = 12
        measurementsRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            discoveryLabel,
            titleLabel,
            mineralCard,
            geoCard,
            measurementsRow
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(closeButton)
        card.addSubview(stack)
        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
    }

    private func makeCaptionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = AppColors.gray
        return label
    }

    private func makeInfoCard(
        caption: String,
        value: String,
        captionColor: UIColor,
        valueColor: UIColor
    ) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(red: 1, green: 0.97, blue: 0.88, alpha: 1)
        container.layer.cornerRadius = 12

        let captionLabel = makeCaptionLabel(caption)
        captionLabel.textColor = captionColor

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .boldSystemFont(ofSize: 16)
        valueLabel.textColor = valueColor

        let stack = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func makeGeoCard() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(red: 0.93, green: 0.97, blue: 0.93, alpha: 1)
        container.layer.cornerRadius = 12

        let titleLabel = UILabel()
        titleLabel.text = "Geo Coordinates"
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = UIColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)

        let latRow = makeCoordinateRow(
            title: "Latitude",
            value: formatCoordinateAxis(mineral.latitude, isLatitude: true)
        )
        let lonRow = makeCoordinateRow(
            title: "Longitude",
            value: formatCoordinateAxis(mineral.longitude, isLatitude: false)
        )

        let stack = UIStackView(arrangedSubviews: [titleLabel, latRow, lonRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func makeCoordinateRow(title: String, value: String) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = AppColors.gray

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .boldSystemFont(ofSize: 13)
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.distribution = .fillEqually
        return row
    }

    private func makeMeasurementCard(caption: String, value: String, unit: String) -> UIView {
        let container = UIView()
        container.backgroundColor = AppColors.lightGray
        container.layer.cornerRadius = 12

        let captionLabel = makeCaptionLabel(caption)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .boldSystemFont(ofSize: 22)

        let unitLabel = UILabel()
        unitLabel.text = unit
        unitLabel.font = .systemFont(ofSize: 13)
        unitLabel.textColor = AppColors.gray

        let valueRow = UIStackView(arrangedSubviews: [valueLabel, unitLabel])
        valueRow.axis = .horizontal
        valueRow.spacing = 4
        valueRow.alignment = .lastBaseline

        let stack = UIStackView(arrangedSubviews: [captionLabel, valueRow])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func formattedDiscoveryType() -> String {
        switch mineral.treasureType.lowercased() {
        case "hidden":
            return "Hidden Treasure"
        case "natural":
            return "Natural Minerals"
        default:
            return mineral.treasureType.capitalized
        }
    }

    private func formattedMineralTypeName() -> String {
        let name = mineral.mineralTypeId.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Mineral" }
        return "Type: \(name)"
    }

    private func formatCoordinateAxis(_ value: Double, isLatitude: Bool) -> String {
        let direction: String
        if isLatitude {
            direction = value >= 0 ? "N" : "S"
        } else {
            direction = value >= 0 ? "E" : "W"
        }
        return String(format: "%.4f° %@", abs(value), direction)
    }

    private func formatMeasurement(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
