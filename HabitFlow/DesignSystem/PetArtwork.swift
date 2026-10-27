import SwiftUI

/// Единая подача картинки питомца во всех списках и окнах.
///
/// - `.fit` по пропорциям картинки: питомец никогда не сплющивается и не растягивается;
/// - `.high` + `antialiased`: чистый край при любом масштабе;
/// - тонкая тень-«подложка» отделяет силуэт от стекла карточки и скрывает остатки каймы
///   (сами края PNG уже вычищены `tools/defringe_pets.py`).
struct PetArtwork: View {
    let character: CompanionCharacter
    /// Мягкая подложка. В больших сценах, где есть своё свечение, её выключают.
    var rim = true

    var body: some View {
        let image = Image(character.imageName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
        if rim {
            image.shadow(color: .black.opacity(0.22), radius: 1.6, y: 1)
        } else {
            image
        }
    }
}
