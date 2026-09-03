async function fetchProfile(id) {
  const res = await fetch(`https://api.example.com/users/${id}`, {
    headers: { Authorization: `Bearer ${process.env.API_KEY}` },
  });
  return res.json();
}

export { fetchProfile };
