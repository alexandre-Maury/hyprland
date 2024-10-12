#!/bin/bash

# Demander à l'utilisateur le nombre de partitions à créer
read -p "Combien de partitions souhaitez-vous créer ? " num_partitions

# Vérifier si le nombre est valide (un entier positif)
if ! [[ "$num_partitions" =~ ^[0-9]+$ ]] || [ "$num_partitions" -le 0 ]; then
  echo "Erreur : Veuillez entrer un nombre entier positif."
  exit 1
fi

# Boucle pour demander les détails de chaque partition
for ((i = 1; i <= num_partitions; i++)); do
  read -p "Entrez la taille de la partition $i (en Mo) : " partition_size
  read -p "Entrez le type de la partition $i (par ex. ext4, swap, etc.) : " partition_type
  echo "Création de la partition $i de taille ${partition_size}Mo et de type $partition_type..."
  # Ajoute ici la commande pour créer la partition (ex: avec parted ou fdisk)
  # Exemple avec parted :
  # parted /dev/sda mkpart primary $partition_type ${partition_size}M
done

echo "Partitions créées avec succès."
